# shellcheck shell=bash disable=SC2034 # sourced by bin/auth, which reads these variables
# Shared sign-in flows for auth/ services, sourced by bin/auth after lib/ui.sh.
#
# Every CLI's headless sign-in is one of two shapes, so services only describe
# theirs and call one of these:
#
#   auth_paste_flow  CLI prints a long link, then waits for a code pasted back
#                    (gcloud, aws login, claude)
#   auth_device_flow CLI prints a link and a short code, then finishes by itself
#                    once you approve on the website (gh, vercel, aws sso)
#
# Both hide the CLI's own output and show a phone-sized card instead, with a short
# link (http://<host>:8085) served only on the tailnet while the flow runs, that
# redirects to the CLI's link. The raw output goes to a log, shown if it fails.
#
# Usage: auth_paste_flow  <url-regex> [hint-param] -- <command...>
#        auth_device_flow <url-regex> <code-regex> -- <command...>
# The card's title and account come from SVC_NAME and AUTH_WHO.

auth_paste_flow() {
  local url_re="$1" hint=""; shift
  [ "$1" != "--" ] && { hint="$1"; shift; }
  shift
  AUTH_FLOW=paste AUTH_URL_RE="$url_re" AUTH_CODE_RE="" AUTH_HINT="$hint" _auth_run "$@"
}

auth_device_flow() {
  local url_re="$1" code_re="$2"; shift 3
  AUTH_FLOW=device AUTH_URL_RE="$url_re" AUTH_CODE_RE="$code_re" AUTH_HINT="" _auth_run "$@"
}

_auth_run() {
  local log status filter filter_pid
  log="$(mktemp -t nomad-auth.XXXXXX)"
  export AUTH_FLOW AUTH_URL_RE AUTH_CODE_RE AUTH_HINT AUTH_LOG="$log"
  export AUTH_TITLE="$SVC_NAME" AUTH_WHO="${AUTH_WHO:-}"
  export AUTH_PORT="${AUTH_SHORTLINK_PORT:-8085}"
  AUTH_HOST="$(hostname -s)"; export AUTH_HOST
  AUTH_BIND="$(tailscale ip -4 2>/dev/null | head -1)"; export AUTH_BIND
  export R B DIM FAINT ACC NAME BAD

  exec {filter}> >(perl -e "$_AUTH_FILTER")
  filter_pid=$!
  "$@" >&"$filter" 2>&1
  status=$?
  exec {filter}>&- # the filter sees EOF, stops the short link, finishes printing
  wait "$filter_pid" 2>/dev/null
  [ "$status" -ne 0 ] && _auth_show_log "$log"
  rm -f "$log"
  return "$status"
}

# Last few meaningful lines of the CLI's own output, for when sign-in fails.
_auth_show_log() {
  printf '\n  %s%s%s\n' "$BAD" "What the CLI said:" "$R"
  sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g' "$1" | tr '\r' '\n' |
    grep -v -E '^\s*$|Waiting for auth|https?://\S{80,}' | tail -6 | sed "s/^/  ${FAINT}/; s/\$/${R}/"
}

read -r -d '' _AUTH_FILTER <<'PERL'
use IO::Socket::INET;
$| = 1;
my %E = %ENV;
my ($buf, $url, $code, $carded, $prompted, $server, $url_at) = ("", "", "", 0, 0, 0, 0);
open(my $log, ">>", $E{AUTH_LOG});
my $url_re = qr/$E{AUTH_URL_RE}/;
my $code_re = length $E{AUTH_CODE_RE} ? qr/$E{AUTH_CODE_RE}/ : undef;

sub serve { my $u = shift;
  return 0 unless $E{AUTH_BIND};
  my $sock = IO::Socket::INET->new(LocalAddr => $E{AUTH_BIND}, LocalPort => $E{AUTH_PORT},
    Listen => 5, ReuseAddr => 1) or return 0;
  my $pid = fork() // return 0;
  if ($pid == 0) {
    close STDIN; alarm 900; # gives up after 15 minutes either way
    while (my $c = $sock->accept) {
      while (my $l = <$c>) { last if $l =~ /^\r?\n$/ }
      print $c "HTTP/1.1 302 Found\r\nLocation: $u\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
      close $c;
    }
    exit 0;
  }
  close $sock; $server = $pid; 1 }

sub card {
  my $short = serve($url) ? "http://$E{AUTH_HOST}:$E{AUTH_PORT}" : "";
  my ($r, $b, $dim, $faint, $acc, $name) = @E{qw(R B DIM FAINT ACC NAME)};
  my $o = "\n  $acc$b◆ $E{AUTH_TITLE}$r\n";
  $o .= "    $dim$E{AUTH_WHO}$r\n" if length $E{AUTH_WHO};
  $o .= "\n  ${acc}1$r  Open this on your phone\n";
  $o .= $short ? "     $name$b$short$r\n" : "     $name$url$r\n";
  if ($E{AUTH_FLOW} eq "paste") {
    $o .= "\n  ${acc}2$r  Sign in, then copy the code\n";
    $o .= "\n  ${acc}3$r  Paste it here\n";
  } else {
    if (length $code) {
      if (index($url, $code) >= 0) {
        $o .= "\n  ${acc}2$r  Check the code  $acc$b$code$r\n     ${faint}(already filled in)$r\n";
      } else {
        $o .= "\n  ${acc}2$r  Enter the code  $acc$b$code$r\n";
      }
    }
    $o .= "\n  ${acc}" . (length $code ? 3 : 2) . "$r  Approve. This finishes by itself.\n";
    $o .= "\n  ${faint}waiting for you…$r\n";
  }
  print STDERR $o; $carded = 1 }

sub line { my $s = shift;
  my $plain = $s; $plain =~ s/\e\[[0-9;?]*[a-zA-Z]//g;
  if (!$url && $plain =~ /($url_re)/) {
    $url = $1; $url_at = time;
    $url .= ($url =~ /\?/ ? "&" : "?") . $E{AUTH_HINT} if length $E{AUTH_HINT};
  }
  if ($code_re && !$code) { $code = $1 if $plain =~ $code_re; }
  if ($code_re && !$code && $url =~ $code_re) { $code = $1; }
  card() if !$carded && $url && (!$code_re || $code);
}

sub idle {
  # A device flow whose code never showed up: show the card without it.
  card() if !$carded && $url && time - $url_at >= 2;
  # A paste flow's CLI is now waiting at its own prompt (a line with no newline):
  # hide that and show ours.
  if ($carded && !$prompted && $E{AUTH_FLOW} eq "paste" && length $buf) {
    print STDERR "\n  $E{ACC}›$E{R} "; $prompted = 1; $buf = "";
  }
}

while (1) {
  my $rin = ""; vec($rin, fileno(STDIN), 1) = 1;
  if (select($rin, undef, undef, 0.3) > 0) {
    sysread(STDIN, my $chunk, 4096) or last;
    print $log $chunk;
    $buf .= $chunk;
    line($1) while $buf =~ s/^(.*?)(?:\r\n|\n|\r)//;
    line($buf) if length $buf;
  } else { idle() }
}
print STDERR "\n";
kill "TERM", $server if $server;
PERL
