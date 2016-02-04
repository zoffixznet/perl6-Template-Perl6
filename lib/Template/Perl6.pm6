unit class Template::Perl6:ver<1.001001>;

use String::Quotemeta;

has $.code = '';
has $.auto-escape;
has $.unparsed = '';
has @.tree;

has $.tag-start       = '<%';
has $.replace-mark    = '%';
has $.expression-mark = '=';
has $.escape-mark     = '=';
has $.capture-end     = 'end';
has $.comment-mark    = '#';
has $.capture-start   = 'begin';
has $.trim-mark       = '=';
has $.tag-end         = '%>';
has $.line-start      = '%';

method build {
    my $escape = $!auto-escape;

    my @blocks = ('');
    my ($i, $capture, $multi);
    while (++$i <= @!tree && (my $next = @!tree[$i])) {
        my ($op, $value) = @!tree[$i - 1];
        @blocks.push: '' and next if $op eq 'line';
        $value //= '';
        my $newline = so $value ~~ /\n$/;
        $value .= chomp;

        # Text (quote and fix line ending)
        if $op eq 'text' {
            $value = join "\n", map { quotemeta }, split "\n", $value;
            $value ~= '\n' if $newline;
            @blocks[*-1] ~= "\$_O ~= \"" ~ $value ~ "\";" if $value ne '';
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
            elsif (!$multi) { @blocks[*-1] ~= "\$_O ~= scalar + $value" }

            # Multi-line
            $multi = !$next || $next[0] ne 'text';

            # Append semicolon
            @blocks[*-1] ~= ';' unless $multi || $capture;
        }

        # Capture start
        if ($op eq 'cpst') { $capture = 1 }
        elsif ($capture) {
            @blocks[*-1] ~= " sub \{ my \$_O = ''; ";
            $capture = 0;
        }
    }

    $!code = join "\n", @blocks;
    @!tree = ();
    return self.code;
}

method parse (Str $template) {
    $!unparsed = $template;
    @!tree = ();

    my $tag     = $!tag-start;
    my $replace = $!replace-mark;
    my $expr    = $!expression-mark;
    my $escp    = $!escape-mark;
    my $cpen    = $!capture-end;
    my $cmnt    = $!comment-mark;
    my $cpst    = $!capture-start;
    my $trim    = $!trim-mark;
    my $end     = $!tag-end;
    my $start   = $!line-start;

    my $line-re = rx/^
            (\s*) $start [ ($replace)||($cmnt)||($expr) ]? (<-[\n]>*)
        $/;

    my $token-re = rx/
        (
            $tag [ $replace || $cmnt ]                     # Replace
        ||
            $tag $expr [$escp]? [\s* $cpen <!before \w>]? # Expression
        ||
            $tag  [\s* $cpen <!before \w>]?               # Code
        ||
            [<!after \w> $cpst \s*]?  [$trim]?  $end      # End
        )
    /;

    my $cpen-re = rx/^ $tag [$expr]? [$escp]? \s* $cpen (<-[\n]>*) $/;
    my $end-re  = rx/^  [($cpst) \s*]? [($trim)]? $end $/;

    # Split lines
    my $op = 'text';
    my ($trimming, $capture);
    for $template.lines {
        my $line = $_;
        # Turn Perl line into mixed line
        if $op eq 'text' && $line ~~ $line-re {

            # Escaped start
            if $1 { $line = "$0$start$4" }

            # Comment
            elsif $2 { $line = "$tag$2 $trim$end" }

            # Expression or code
            else { $line = $3 ?? "$0$tag$3$4 $end" !! "$tag$4 $trim$end" }
        }

        # Escaped line ending
        $line ~= "\n" if $line !~~ s/\\\\$/\\\n/ && $line !~~ s/\\$//;

        # Mixed line
        for split $token-re, $line, :v {
            my $token = $_;

            # Capture end
            ($token, $capture) = ("$tag$0", 1) if $token ~~ $cpen-re;

            # End
            if $op ne 'text' and $token ~~ $end-re {
                $op = 'text';

                # Capture start
                splice @!tree, -1, 0, ['cpst'] if $0;

                # Trim left side
                _trim(@!tree) if ($trimming = $1) and @!tree > 1;

                # Hint at end
                @!tree.push: ['text', ''];
            }

            # Code
            elsif $token eq $tag { $op = 'code' }

            # Expression
            elsif $token eq "$tag$expr" { $op = 'expr' }

            # Expression that needs to be escaped
            elsif $token eq "$tag$expr$escp" { $op = 'escp' }

            # Comment
            elsif $token eq "$tag$cmnt" { $op = 'cmnt' }

            # Text (comments are just ignored)
            elsif $op ne 'cmnt' {

                # Replace
                $token = $tag if $token eq "$tag$replace";

                # Trim right side (convert whitespace to line noise)
                if $trimming and $token ~~ s/^(\s+)// {
                    @!tree.push: ['code', ~$0];
                    $trimming = 0;
                }

                # Token (with optional capture end)
                @!tree.push: ['cpen'] if $capture;
                @!tree.push: [$op, $token];
                $capture = 0;
            }
        }

        # Optimize successive text lines separated by a newline
        @!tree.push: ['line'] and next
            if @!tree[*-4] && @!tree[*-4][0] ne 'line'
            || (!@!tree[*-3] || @!tree[*-3][0] ne 'text' || @!tree[*-3][1] !~~ /\n$/)
            || (@!tree[*-2][0] ne 'line' || @!tree[*-1][0] ne 'text');
        @!tree[*-3][1] ~= (@!tree.pop)[1];
    }

    return self;
}

method render (Str $template, *@args) {
    return self.parse($template)#.build.compile
        # || self.interpret(*@args);
}


sub _trim (@tree) {
    # Skip captures
    my $i = @tree[*-2][0] eq 'cpst' || @tree[*-2][0] eq 'cpen' ?? 3 !! 2;

    # Only trim text
    return unless @tree[* - $i][0] eq 'text';

    # Convert whitespace text to line noise
    splice @tree, *-$i, 0, ['code', $0] if @tree[*-$i][1] ~~ s/(\s+)$//;
}
