#!/usr/bin/env perl6

use lib 'lib';
use Template::Perl6;

my $mt = Template::Perl6.new;
my $output = $mt.render(q:to/EOF/);
<!DOCTYPE html>
<html>
  <head><title>Simple</title></head>
  % my $now = DateTime.now;
  <body>Time: <%= $now %></body>
</html>
EOF
use Data::Dump;
say Dump $mt.build;

=finish

#!/usr/bin/env perl6

use lib 'lib';
use 5.022;
use Mojo::Template;

my $mt = Mojo::Template->new;
my $output = $mt->parse(<<'EOF');
<!DOCTYPE html>
<html>
  <head><title>Simple</title></head>
  % my $now = time;
  <body>Time: <%= $now %></body>
</html>
EOF
use Data::Dumper;
say Dumper $mt->tree;


__END__
