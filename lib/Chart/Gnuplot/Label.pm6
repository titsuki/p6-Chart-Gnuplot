use v6;
unit class Chart::Gnuplot::Label;

use Chart::Gnuplot::Util;

my subset LabelRotate of Cool where { if not $_.defined { True } elsif $_ ~~ Bool and $_ == True { False } else { $_ ~~ Real or ($_ ~~ Bool and $_ == False) } };
my subset FalseOnly of Bool where { if not $_.defined { True } else { $_ == False } }
my subset TrueOnly of Bool where { if not $_.defined { True } else { $_ == True } }

has &!writer;

submethod BUILD(:&!writer) { }

method writer(&writer) {
    &!writer = &writer;
    self
}

method label(:$tag, :$label-text, :$at, :$left, :$center, :$right,
             LabelRotate :$rotate, :$font-name, :$font-size, FalseOnly :$enhanced,
             :$front, :$back, :$textcolor, FalseOnly :$point, :$line-type, :$point-type, :$point-size, :$offset,
             :$boxed, :$hypertext, :&writer? = -> $msg { self.command: $msg }) {
    my @args;
    @args.push($tag) if $tag.defined;
    @args.push(sprintf("\"%s\"", $label-text)) if $label-text.defined;

    @args.push(tweak-coordinate(:name("at"), :coordinate($at)));
    @args.push("left") if $left.defined;
    @args.push("center") if $center.defined;
    @args.push("right") if $right.defined;

    if $rotate.defined {
        given $rotate {
            when $_ ~~ Bool and $_ == False { @args.push("norotate") }
            when * ~~ Real { @args.push("rotate by $rotate") }
            default { die "Error: Something went wrong." }
        }
    }

    @args.push(tweak-fontargs(:$font-name, :$font-size));
    @args.push("noenhanced") if $enhanced.defined and $enhanced == False;
    @args.push("front") if $front.defined;
    @args.push("back") if $back.defined;
    @args.push("textcolor " ~ $textcolor) if $textcolor.defined;
    @args.push("nopoint") if $point.defined and $point == False;

    my @point-args;
    @point-args.push("lt " ~ $line-type) if $line-type.defined;
    @point-args.push("pt " ~ $point-type) if $point-type.defined;
    @point-args.push("ps " ~ $point-size) if $point-size.defined;

    @args.push("point " ~ @point-args.join(" ")) if @point-args.elems > 0;

    @args.push(tweak-coordinate(:name("offset"), :coordinate($offset)));
    @args.push("boxed") if $boxed.defined;
    @args.push("hypertext") if $hypertext.defined;

    &writer(sprintf("set label %s", @args.grep(* ne "").join(" ")));
}

my subset AnyLabelRotate of Cool where { if not $_.defined { True } elsif $_ ~~ Bool and $_ == True { False } else { $_ eq "parallel" or $_ ~~ Real or ($_ ~~ Bool and $_ == False) } };

method !anylabel(Str :$label, :$offset, :$font-name, :$font-size, :$textcolor, Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = -> $msg { self.command: $msg }) {
    my @args;
    @args.push(sprintf("\"%s\"", $label)) if $label.defined;
    @args.push(tweak-coordinate(:name("offset"), :coordinate($offset)));
    @args.push(tweak-fontargs(:$font-name, :$font-size));
    @args.push("textcolor " ~ $textcolor) if $textcolor.defined;
    @args.push($enhanced ?? "enhanced" !! "noenhanced") if $enhanced.defined;
    
    if $rotate.defined {
        given $rotate {
            when $_ ~~ Bool and $_ == False { @args.push("norotate") }
            when * ~~ Real { @args.push("rotate by $rotate") }
            when * eq "parallel" { @args.push("rotate parallel") }
            default { die "Error: Something went wrong." }
        }
    }
    @args.grep(* ne "").join(" ");
}

method xlabel(Str :$label, :$offset, :$font-name, :$font-size, :$textcolor, Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = &!writer) {
    &writer(sprintf("set xlabel %s", self!anylabel(:$label, :$offset, :$font-name, :$font-size, :$textcolor, :$enhanced, :$rotate)));
}

method ylabel(Str :$label, :$offset, :$font-name, :$font-size, :$textcolor, Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = &!writer) {
    &writer(sprintf("set ylabel %s", self!anylabel(:$label, :$offset, :$font-name, :$font-size, :$textcolor, :$enhanced, :$rotate)));
}

method zlabel(Str :$label, :$offset, :$font-name, :$font-size, :$textcolor, Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = &!writer) {
    &writer(sprintf("set zlabel %s", self!anylabel(:$label, :$offset, :$font-name, :$font-size, :$textcolor, :$enhanced, :$rotate)));
}

method x2label(Str :$label, :$offset, :$font-name, :$font-size, :$textcolor, Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = &!writer) {
    &writer(sprintf("set x2label %s", self!anylabel(:$label, :$offset, :$font-name, :$font-size, :$textcolor, :$enhanced, :$rotate)));
}

method y2label(Str :$label, :$offset, :$font-name, :$font-size, :$textcolor, Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = &!writer) {
    &writer(sprintf("set y2label %s", self!anylabel(:$label, :$offset, :$font-name, :$font-size, :$textcolor, :$enhanced, :$rotate)));
}

method cblabel(Str :$label, :$offset, :$font-name, :$font-size, :$textcolor, Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = &!writer) {
    &writer(sprintf("set cblabel %s", self!anylabel(:$label, :$offset, :$font-name, :$font-size, :$textcolor, :$enhanced, :$rotate)));
}

