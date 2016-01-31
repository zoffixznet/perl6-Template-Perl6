unit class Template::Perl6:ver<1.001001>;

has $.append = '';
has $.code   = '';
has $.prepend = '';
has $.unparsed = '';
has $.auto-escape;
has $.compiled;
has $.capture_end     = 'end';
has $.capture-start   = 'begin';
has $.comment-mark    = '#';
has $.encoding        = 'UTF-8';
has $.escape          = sub { };
has $.escape-mark     = '=';
has $.expression-mark = '=';
has $.trim-mark       = '=';
has $.line-start      = '%';
has $.replace-mark    = '%';
has $.name            = 'template';
has $.namespace       = 'Template::Perl6::SandBox';
has $.tag-start       = '<%';
has $.tag-end         = '%>';
has @.tree;

method build {
  my $self = shift;

  my $escape = $.auto-escape;

  my @blocks = ('');
  my ($i, $capture, $multi);
  while (++$i <= @.tree && (my $next = @.tree[$i])) {
    my ($op, $value) = @.tree[$i - 1];
    push @blocks, '' and next if $op eq 'line';
    my $newline = chomp($value //= '');

    # Text (quote and fix line ending)
    if ($op eq 'text') {
      $value = join "\n", map { quotemeta $_ }, split("\n", $value, -1);
      $value ~= '\n' if $newline;
      @blocks[*-1] ~= "\$_O .= \"" ~ $value ~ "\";" if $value ne '';
    }

    # Code or multi-line expression
    elsif ($op eq 'code' || $multi) { @blocks[*-1] ~= $value }

    # Capture end
    elsif ($op eq 'cpen') {
      @blocks[*-1] ~= 'return Mojo::ByteStream->new($_O) }';

      # No following code
      @blocks[*-1] ~= ';' if ($next[1] // '') ~~ /^\s*$/;
    }

    # Expression
    if ($op eq 'expr' || $op eq 'escp') {

      # Escaped
      if (!$multi && ($op eq 'escp' && !$escape || $op eq 'expr' && $escape)) {
        @blocks[*-1] ~= "\$_O ~= _escape scalar + $value";
      }

      # Raw
      elsif (!$multi) { @blocks[*-1] ~= "\$_O .= scalar + $value" }

      # Multi-line
      $multi = !$next || $next[0] ne 'text';

      # Append semicolon
      @blocks[*-1] ~= ';' unless $multi || $capture;
    }

    # Capture start
    if ($op eq 'cpst') { $capture = 1 }
    elsif ($capture) {
      @blocks[*-1] ~= " sub \{ my \$_O = ''; "; # }" }" comment is workaround for broken highlights
      $capture = 0;
    }
  }

  return $self.code(join "\n", @blocks).tree([]);
}

method compile {
  my $self = shift;

  # Compile with line directive
  return Nil unless defined(my $code = $self.code);
  my $compiled = eval self._wrap($code);
  self.compiled($compiled) and return Nil;
}

method interpret {
  my $self = shift;

  return Nil unless my $compiled = $self.compiled;
  my $output;
  return $output if eval { $output = $compiled(@_); 1 };
}

method parse {
  my ($self, $template) = @_;

  # Clean start
  $self.unparsed($template).tree(\my @tree);

  my $tag     = $self.tag_start;
  my $replace = $self.replace_mark;
  my $expr    = $self.expression_mark;
  my $escp    = $self.escape_mark;
  my $cpen    = $self.capture_end;
  my $cmnt    = $self.comment_mark;
  my $cpst    = $self.capture_start;
  my $trim    = $self.trim_mark;
  my $end     = $self.tag_end;
  my $start   = $self.line_start;

  my $line_re
    = rx/^(\s*) $start (?:( $replace )|( $cmnt )|( $expr ))?(.*)$/;
  my $token_re = rx/
    (
      $tag (?: $replace | $cmnt )                   # Replace
    |
      $tag$expr (?: $escp )?(?:\s* $cpen (?!\w))?   # Expression
    |
      $tag (?:\s* $cpen (?!\w))?                      # Code
    |
      (?:(?<!\w) $cpst \s*)?(?: $trim )? $end       # End
    )
  /x;
  my $cpen_re = rx/^\Q$tag\E(?:\Q$expr\E)?(?:\Q$escp\E)?\s*\Q$cpen\E(.*)$/;
  my $end_re  = rx/^(?:(\Q$cpst\E)\s*)?(\Q$trim\E)?\Q$end\E$/;

  # Split lines
  my $op = 'text';
  my ($trimming, $capture);
  for my $line (split "\n", $template) {

    # Turn Perl line into mixed line
    if ($op eq 'text' && $line =~ $line_re) {

      # Escaped start
      if ($2) { $line = "$1$start$5" }

      # Comment
      elsif ($3) { $line = "$tag$3 $trim$end" }

      # Expression or code
      else { $line = $4 ? "$1$tag$4$5 $end" : "$tag$5 $trim$end" }
    }

    # Escaped line ending
    $line .= "\n" if $line !~ s/\\\\$/\\\n/ && $line !~ s/\\$//;

    # Mixed line
    for my $token (split $token_re, $line) {

      # Capture end
      ($token, $capture) = ("$tag$1", 1) if $token =~ $cpen_re;

      # End
      if ($op ne 'text' && $token =~ $end_re) {
        $op = 'text';

        # Capture start
        splice @tree, -1, 0, ['cpst'] if $1;

        # Trim left side
        _trim(\@tree) if ($trimming = $2) && @tree > 1;

        # Hint at end
        push @tree, ['text', ''];
      }

      # Code
      elsif ($token eq $tag) { $op = 'code' }

      # Expression
      elsif ($token eq "$tag$expr") { $op = 'expr' }

      # Expression that needs to be escaped
      elsif ($token eq "$tag$expr$escp") { $op = 'escp' }

      # Comment
      elsif ($token eq "$tag$cmnt") { $op = 'cmnt' }

      # Text (comments are just ignored)
      elsif ($op ne 'cmnt') {

        # Replace
        $token = $tag if $token eq "$tag$replace";

        # Trim right side (convert whitespace to line noise)
        if ($trimming && $token =~ s/^(\s+)//) {
          push @tree, ['code', $1];
          $trimming = 0;
        }

        # Token (with optional capture end)
        push @tree, $capture ? ['cpen'] : (), [$op, $token];
        $capture = 0;
      }
    }

    # Optimize successive text lines separated by a newline
    push @tree, ['line'] and next
      if $tree[-4] && $tree[-4][0] ne 'line'
      || (!$tree[-3] || $tree[-3][0] ne 'text' || $tree[-3][1] !~ /\n$/)
      || ($tree[-2][0] ne 'line' || $tree[-1][0] ne 'text');
    $tree[-3][1] .= pop(@tree)->[1];
  }

  return $self;
}

method render {
  my $self = shift;
  return $self.parse(shift)->build->compile || $self->interpret(@_);
}

method render_file {
  my ($self, $path) = (shift, shift);

  $self->name($path) unless defined $self->{name};
  my $template = slurp $path;
  my $encoding = $self->encoding;
  croak qq{Template "$path" has invalid encoding}
    if $encoding && !defined($template = decode $encoding, $template);

  return $self->render($template, @_);
}

method _line {
  my $name = shift->name;
  $name =~ y/"//d;
  return qq{#line @{[shift]} "$name"};
}

method _trim {
  my $tree = shift;

  # Skip captures
  my $i = $tree->[-2][0] eq 'cpst' || $tree->[-2][0] eq 'cpen' ? -3 : -2;

  # Only trim text
  return unless $tree->[$i][0] eq 'text';

  # Convert whitespace text to line noise
  splice @$tree, $i, 0, ['code', $1] if $tree->[$i][1] =~ s/(\s+)$//;
}

method _wrap {
  my ($self, $code) = @_;

  # Escape function
  monkey_patch $self->namespace, '_escape', $self->escape;

  # Wrap lines
  my $num = () = $code =~ /\n/g;
  my $head = $self->_line(1) . "\npackage @{[$self->namespace]};";
  $head .= " use Mojo::Base -strict; no warnings 'ambiguous';";
  $code = "$head sub { my \$_O = ''; @{[$self->prepend]}; { $code\n";
  $code .= $self->_line($num + 1) . "\n@{[$self->append]}; } \$_O };";

  warn "-- Code for @{[$self->name]}\n@{[encode 'UTF-8', $code]}\n\n" if DEBUG;
  return $code;
}
