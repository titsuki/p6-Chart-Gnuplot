use v6;
unit class Chart::Gnuplot;

has $!gnuplot;
has $!style;
has Bool $.persist;
has $.debug;
has $.terminal;
has %.options;
has $!filename;
has Int $!num-plot;
has $!promise;
has @!msg-pool;

my subset FalseOnly of Bool where { if not $_.defined { True } else { $_ == False } }
my subset TrueOnly of Bool where { if not $_.defined { True } else { $_ == True } }

submethod BUILD(:$!terminal!, Str :$!filename, :$!persist = True, :$!debug = False) {
    my $HOME = qq:x/echo \$HOME/.subst(/\s*/,"",:g);
    my $prefix = "$HOME/.p6chart-gnuplot";

    my @opts;
    @opts.push('-persist') if $!persist;
    $!gnuplot = Proc::Async.new(:w, "$prefix/bin/gnuplot", @opts.join(" "));

    if $!debug {
        $!gnuplot.stderr.act(-> $v { @!msg-pool.push($v); });
        $!gnuplot.stdout.act(-> $v { @!msg-pool.push($v); });
    } else {
        $!gnuplot.stderr.act({;});
        $!gnuplot.stdout.act({;});
    }
    $!promise = $!gnuplot.start;
    $!num-plot = 0;
}

submethod DESTROY {
    $!gnuplot.close-stdin;
    await $!promise;
}

method terminal($terminal, :&writer? = -> $msg { self.command: $msg }) {
    $!terminal = $terminal;
    &writer(sprintf("set terminal %s", $!terminal));
}

method !tweak-fontargs(:$font-name, :$font-size) {
    my @font;
    @font.push($font-name.defined ?? $font-name !! "");
    @font.push($font-size) if $font-size.defined;
    
    (not $font-name.defined and not $font-size.defined) ?? "" !! sprintf("font \"%s\"", @font.join(","));
}

method !tweak-coordinate(Mu :$coordinate!, :$name!, :$enable-nooffset = False, Int :$upper-bound?) {
    my Str $coordinate-str = "";
    if $coordinate.defined {
        given $coordinate {
            when * ~~ FalseOnly and $enable-nooffset { $coordinate-str = "nooffset" }
            when * ~~ Pair {
                $coordinate-str = ($name, sprintf("%s %s", $_.key, $_.value)).join(" ");
            }
            when * ~~ List {
                if $upper-bound.defined and $coordinate.elems > $upper-bound {
                    die "Error: Something went wrong."; # TODO: LTA
                }
                my @coordinate-args;
                for @$coordinate -> $p {
                    given $p {
                        when * ~~ Pair {
                            @coordinate-args.push(sprintf("%s %s", $p.key, $p.value));
                        }
                        when * ~~ Real {
                            @coordinate-args.push(sprintf("%s", $p));
                        }
                        default { die "Error: Something went wrong." } # TODO: LTA
                    }
                }
                $coordinate-str = "$name " ~ @coordinate-args.join(",") if @coordinate-args.elems > 0;
            }
            default { die "Error: Something went wrong." } # TODO: LTA
        }
    }
    $coordinate-str;
}

multi method plot(:$title, :$ignore, :@range, :@vertices!,
                  :@using,
                  Str :$style, :ls(:$linestyle), :lt(:$linetype), :lw(:$linewidth), :lc(:$linecolor),
                  :$pointtype, :$pointsize, :$fill, FalseOnly :$hidden3d, FalseOnly :$contours, FalseOnly :$surface, :$palette,
                  :&writer? = -> $msg { self.command: $msg }) {
    my @args;

    my $tmpvariable = '$mydata' ~ ($*PID, time, @vertices.WHERE).join;
    &writer(sprintf("%s << EOD", $tmpvariable));
    for ^@vertices.elems -> $r {
        &writer(@vertices[$r;*].join(" "));
    }
    &writer("EOD");

    for @range {
        @args.push(sprintf("[%s]", $_.join(":")));
    }

    @args.push($tmpvariable);
    @args.push("using " ~ @using.join(":")) if @using.elems > 0;
    @args.push("with " ~ $style) if $style.defined;

    if $title.defined {
        given $title {
            when * ~~ Str { @args.push(sprintf("title \"%s\"", $title)) }
            when * == False { @args.push(sprintf("notitle")) }
        }
    }

    @args.push(sprintf("notitle [%s]", $ignore)) if $ignore.defined;


    @args.push("linestyle " ~ $linestyle) if $linestyle.defined;
    @args.push("linetype " ~ $linetype) if $linetype.defined;
    @args.push("linewidth " ~ $linewidth) if $linewidth.defined;
    @args.push("linecolor " ~ $linecolor) if $linecolor.defined;
    @args.push("pointtype " ~ $pointtype) if $pointtype.defined;
    @args.push("pointsize " ~ $pointsize) if $pointsize.defined;
    @args.push("fill " ~ $fill) if $fill.defined;
    @args.push("nohidden3d") if $hidden3d.defined and $hidden3d == False;
    @args.push("nocontours") if $contours.defined and $contours == False;
    @args.push("nosurface") if $surface.defined and $surface == False;
    @args.push("palette") if $palette.defined;

    &writer(sprintf("set terminal %s", $!terminal));
    &writer(sprintf("set output \"%s\"", $!filename));

    my $cmd = do given $!num-plot {
        when * > 0 { "replot" }
        default { "plot" }
    };
    &writer(sprintf("%s %s",$cmd, @args.grep(* ne "").join(" ")));
    $!num-plot++;
}

multi method plot(:$title, :$ignore, :@range, :$function!,
                  Str :$style, :ls(:$linestyle), :lt(:$linetype), :lw(:$linewidth), :lc(:$linecolor),
                  :$pointtype, :$pointsize, :$fill, FalseOnly :$hidden3d, FalseOnly :$contours, FalseOnly :$surface, :$palette,
                  :&writer? = -> $msg { self.command: $msg }) {
    my @args;

    for @range {
        @args.push(sprintf("[%s]", $_.join(":")));
    }
    
    @args.push($function) if $function.defined;

    if $title.defined {
        given $title {
            when * ~~ Str { @args.push(sprintf("title \"%s\"", $title)) }
            when * == False { @args.push(sprintf("notitle")) }
        }
    }

    @args.push(sprintf("notitle [%s]", $ignore)) if $ignore.defined;

    @args.push("with " ~ $style) if $style.defined;

    @args.push("linestyle " ~ $linestyle) if $linestyle.defined;
    @args.push("linetype " ~ $linetype) if $linetype.defined;
    @args.push("linewidth " ~ $linewidth) if $linewidth.defined;
    @args.push("linecolor " ~ $linecolor) if $linecolor.defined;
    @args.push("pointtype " ~ $pointtype) if $pointtype.defined;
    @args.push("pointsize " ~ $pointsize) if $pointsize.defined;
    @args.push("fill " ~ $fill) if $fill.defined;
    @args.push("nohidden3d") if $hidden3d.defined and $hidden3d == False;
    @args.push("nocontours") if $contours.defined and $contours == False;
    @args.push("nosurface") if $surface.defined and $surface == False;
    @args.push("palette") if $palette.defined;

    &writer(sprintf("set terminal %s", $!terminal));
    &writer(sprintf("set output \"%s\"", $!filename));

    my $cmd = do given $!num-plot {
        when * > 0 { "replot" }
        default { "plot" }
    };

    &writer(sprintf("%s %s", $cmd, @args.grep(* ne "").join(" ")));
    $!num-plot++;
}

multi method splot(:@range,
                   :@vertices!,
                   :$binary, :$matrix, :$index, :$every,
                   :$title, :$style, :ls(:$linestyle), :lt(:$linetype), :lw(:$linewidth), :lc(:$linecolor),
                   :$pointtype, :$pointsize, :$fill, FalseOnly :$hidden3d, FalseOnly :$contours, FalseOnly :$surface, :$palette, :&writer? = -> $msg { self.command: $msg }) {
    my @args;

    for @range {
        @args.push(sprintf("[%s]", $_.join(":")));
    }

    my $tmpvariable = '$mydata' ~ ($*PID, time, @vertices.WHERE).join;
    &writer(sprintf("%s << EOD", $tmpvariable));
    for ^@vertices.elems -> $r {
        &writer(@vertices[$r;*].join(" "));
    }
    &writer("EOD");

    @args.push($tmpvariable);

    @args.push("binary") if $binary.defined;
    @args.push("matrix") if $matrix.defined;
    @args.push("index") if $index.defined;
    @args.push("every") if $every.defined;

    if $title.defined {
        given $title {
            when * ~~ Str { @args.push(sprintf("title \"%s\"", $title)) }
            when * == False { @args.push(sprintf("notitle")) }
        }
    }

    @args.push("with " ~ $style) if $style.defined;

    @args.push("linestyle " ~ $linestyle) if $linestyle.defined;
    @args.push("linetype " ~ $linetype) if $linetype.defined;
    @args.push("linewidth " ~ $linewidth) if $linewidth.defined;
    @args.push("linecolor " ~ $linecolor) if $linecolor.defined;
    @args.push("pointtype " ~ $pointtype) if $pointtype.defined;
    @args.push("pointsize " ~ $pointsize) if $pointsize.defined;
    @args.push("fill " ~ $fill) if $fill.defined;
    @args.push("nohidden3d") if $hidden3d.defined and $hidden3d == False;
    @args.push("nocontours") if $contours.defined and $contours == False;
    @args.push("nosurface") if $surface.defined and $surface == False;
    @args.push("palette") if $palette.defined;

    &writer(sprintf("set terminal %s", $!terminal));
    &writer(sprintf("set output \"%s\"", $!filename));

    my $cmd = do given $!num-plot {
        when * > 0 { "replot" }
        default { "splot" }
    };
    &writer(sprintf("%s %s", $cmd, @args.grep(* ne "").join(" ")));
}

multi method splot(:@range,
                   :$function!,
                   :$title, :$style, :ls(:$linestyle), :lt(:$linetype), :lw(:$linewidth), :lc(:$linecolor),
                   :$pointtype, :$pointsize, :$fill, FalseOnly :$hidden3d, FalseOnly :$contours, FalseOnly :$surface, :$palette, :&writer? = -> $msg { self.command: $msg }) {
    my @args;

    for @range {
        @args.push(sprintf("[%s]", $_.join(":")));
    }

    @args.push($function) if $function.defined;

    if $title.defined {
        given $title {
            when * ~~ Str { @args.push(sprintf("title \"%s\"", $title)) }
            when * == False { @args.push(sprintf("notitle")) }
        }
    }

    @args.push("with " ~ $style) if $style.defined;

    @args.push("linestyle " ~ $linestyle) if $linestyle.defined;
    @args.push("linetype " ~ $linetype) if $linetype.defined;
    @args.push("linewidth " ~ $linewidth) if $linewidth.defined;
    @args.push("linecolor " ~ $linecolor) if $linecolor.defined;
    @args.push("pointtype " ~ $pointtype) if $pointtype.defined;
    @args.push("pointsize " ~ $pointsize) if $pointsize.defined;
    @args.push("fill " ~ $fill) if $fill.defined;
    @args.push("nohidden3d") if $hidden3d.defined and $hidden3d == False;
    @args.push("nocontours") if $contours.defined and $contours == False;
    @args.push("nosurface") if $surface.defined and $surface == False;
    @args.push("palette") if $palette.defined;

    &writer(sprintf("set terminal %s", $!terminal));
    &writer(sprintf("set output \"%s\"", $!filename));

    my $cmd = do given $!num-plot {
        when * > 0 { "replot" }
        default { "splot" }
    };
    &writer(sprintf("%s %s", $cmd, @args.grep(* ne "").join(" ")));
}

my subset LabelRotate of Cool where { if not $_.defined { True } elsif $_ ~~ Bool and $_ == True { False } else { $_ ~~ Real or ($_ ~~ Bool and $_ == False) } };

method label(:$tag, :$label-text, :$at, :$left, :$center, :$right,
             LabelRotate :$rotate, :$font-name, :$font-size, FalseOnly :$enhanced,
             :$front, :$back, :$textcolor, FalseOnly :$point, :$line-type, :$point-type, :$point-size, :$offset,
             :$boxed, :$hypertext, :&writer? = -> $msg { self.command: $msg }) {
    my @args;
    @args.push($tag) if $tag.defined;
    @args.push(sprintf("\"%s\"", $label-text)) if $label-text.defined;

    @args.push(self!tweak-coordinate(:name("at"), :coordinate($at)));
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

    @args.push(self!tweak-fontargs(:$font-name, :$font-size));
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

    @args.push(self!tweak-coordinate(:name("offset"), :coordinate($offset)));
    @args.push("boxed") if $boxed.defined;
    @args.push("hypertext") if $hypertext.defined;

    &writer(sprintf("set label %s", @args.grep(* ne "").join(" ")));
}

my subset AnyLabelRotate of Cool where { if not $_.defined { True } elsif $_ ~~ Bool and $_ == True { False } else { $_ eq "parallel" or $_ ~~ Real or ($_ ~~ Bool and $_ == False) } };

method !anylabel(Str :$label, :$offset, :$font-name, :$font-size, :$textcolor, Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = -> $msg { self.command: $msg }) {
    my @args;
    @args.push(sprintf("\"%s\"", $label)) if $label.defined;
    @args.push(self!tweak-coordinate(:name("offset"), :coordinate($offset)));
    @args.push(self!tweak-fontargs(:$font-name, :$font-size));
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

method xlabel(Str :$label, :$offset, :$font-name, :$font-size, :$textcolor, Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = -> $msg { self.command: $msg }) {
    &writer(sprintf("set xlabel %s", self!anylabel(:$label, :$offset, :$font-name, :$font-size, :$textcolor, :$enhanced, :$rotate)));
}

method ylabel(Str :$label, :$offset, :$font-name, :$font-size, :$textcolor, Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = -> $msg { self.command: $msg }) {
    &writer(sprintf("set ylabel %s", self!anylabel(:$label, :$offset, :$font-name, :$font-size, :$textcolor, :$enhanced, :$rotate)));
}

method zlabel(Str :$label, :$offset, :$font-name, :$font-size, :$textcolor, Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = -> $msg { self.command: $msg }) {
    &writer(sprintf("set zlabel %s", self!anylabel(:$label, :$offset, :$font-name, :$font-size, :$textcolor, :$enhanced, :$rotate)));
}

method x2label(Str :$label, :$offset, :$font-name, :$font-size, :$textcolor, Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = -> $msg { self.command: $msg }) {
    &writer(sprintf("set x2label %s", self!anylabel(:$label, :$offset, :$font-name, :$font-size, :$textcolor, :$enhanced, :$rotate)));
}

method y2label(Str :$label, :$offset, :$font-name, :$font-size, :$textcolor, Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = -> $msg { self.command: $msg }) {
    &writer(sprintf("set y2label %s", self!anylabel(:$label, :$offset, :$font-name, :$font-size, :$textcolor, :$enhanced, :$rotate)));
}

method cblabel(Str :$label, :$offset, :$font-name, :$font-size, :$textcolor, Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = -> $msg { self.command: $msg }) {
    &writer(sprintf("set cblabel %s", self!anylabel(:$label, :$offset, :$font-name, :$font-size, :$textcolor, :$enhanced, :$rotate)));
}

method !anyrange(:$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend) {
    my @args;
    @args.push(sprintf("[%s:%s]", $min, $max));
    @args.push($reverse ?? "reverse" !! "noreverse") if $reverse.defined;
    @args.push($writeback ?? "writeback" !! "nowriteback") if $writeback.defined;
    @args.push($extend ?? "extend" !! "noextend") if $extend.defined;
    @args.grep(* ne "").join(" ");
}

multi method xrange(:$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend, :&writer? = -> $msg { self.command: $msg }) {
   &writer(sprintf("set xrange %s", self!anyrange(:$min, :$max, :$reverse, :$writeback, :$extend)));
}

multi method xrange(:$restore, :&writer? = -> $msg { self.command: $msg }) {
    &writer("set xrange restore");
}

multi method yrange(:$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend, :&writer? = -> $msg { self.command: $msg }) {
   &writer(sprintf("set yrange %s", self!anyrange(:$min, :$max, :$reverse, :$writeback, :$extend)));
}

multi method yrange(:$restore, :&writer? = -> $msg { self.command: $msg }) {
    &writer("set yrange restore");
}

multi method zrange(:$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend, :&writer? = -> $msg { self.command: $msg }) {
   &writer(sprintf("set zrange %s", self!anyrange(:$min, :$max, :$reverse, :$writeback, :$extend)));
}

multi method zrange(:$restore, :&writer? = -> $msg { self.command: $msg }) {
    &writer("set zrange restore");
}

multi method x2range(:$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend, :&writer? = -> $msg { self.command: $msg }) {
   &writer(sprintf("set x2range %s", self!anyrange(:$min, :$max, :$reverse, :$writeback, :$extend)));
}

multi method x2range(:$restore, :&writer? = -> $msg { self.command: $msg }) {
    &writer("set x2range restore");
}

multi method y2range(:$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend, :&writer? = -> $msg { self.command: $msg }) {
   &writer(sprintf("set y2range %s", self!anyrange(:$min, :$max, :$reverse, :$writeback, :$extend)));
}

multi method y2range(:$restore, :&writer? = -> $msg { self.command: $msg }) {
    &writer("set y2range restore");
}

multi method cbrange(:$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend, :&writer? = -> $msg { self.command: $msg }) {
    &writer(sprintf("set cbrange %s", self!anyrange(:$min, :$max, :$reverse, :$writeback, :$extend)));
}

multi method cbrange(:$restore, :&writer? = -> $msg { self.command: $msg }) {
    &writer("set cbrange restore");
}

multi method rrange(:$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend, :&writer? = -> $msg { self.command: $msg }) {
    &writer(sprintf("set rrange %s", self!anyrange(:$min, :$max, :$reverse, :$writeback, :$extend)));
}

multi method rrange(:$restore, :&writer? = -> $msg { self.command: $msg }) {
    &writer("set rrange restore");
}

multi method trange(:$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend, :&writer? = -> $msg { self.command: $msg }) {
    &writer(sprintf("set trange %s", self!anyrange(:$min, :$max, :$reverse, :$writeback,  :$extend)));
}

multi method trange(:$restore, :&writer? = -> $msg { self.command: $msg }) {
    &writer("set trange restore");
}

multi method urange(:$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend, :&writer? = -> $msg { self.command: $msg }) {
    &writer(sprintf("set urange %s", self!anyrange(:$min, :$max, :$reverse, :$writeback, :$extend)));
}

multi method urange(:$restore, :&writer? = -> $msg { self.command: $msg }) {
    &writer("set urange restore");
}

multi method vrange(:$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend, :&writer? = -> $msg { self.command: $msg }) {
    &writer(sprintf("set vrange %s", self!anyrange(:$min, :$max, :$reverse, :$writeback, :$extend)));
}

multi method vrange(:$restore, :&writer? = -> $msg { self.command: $msg }) {
    &writer("set vrange restore");
}

my subset AnyTicsRotate of Cool where { if not $_.defined { True } elsif $_ ~~ Bool and $_ == True { False } else { $_ ~~ Real or ($_ ~~ Bool and $_ == False) } };
my subset AnyTicsOffset of Mu where { if not $_.defined { True } else { $_ ~~ FalseOnly or ($_ ~~ List and $_.all ~~ Pair|Real) } };

method !anytics(:$axis, :$border, Bool :$mirror,
               :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, AnyTicsRotate :$rotate, AnyTicsOffset :$offset,
               :$left, :$right, :$center, :$autojustify,
               :$add,
               :$autofreq,
               :$incr,
               :$start, :$end,
               :@tics where { if not $_.defined { True }
                              else { $_.map(-> $e { $e<label>:exists and $e<pos>:exists }).all == True and $_.map(-> $e { $e.keys.grep(* eq "label"|"pos"|"level").elems == $e.keys.elems }).all == True } },
               :$format, :$font-name, :$font-size, Bool :$enhanced,
               :$numeric, :$timedate, :$geographic,
               :$rangelimited,
               :$textcolor
               ) {
    my @args;
    @args.push("axis") if $axis.defined;
    @args.push("border") if $border.defined;
    @args.push($mirror ?? "mirror" !! "nomirror") if $mirror.defined;
    @args.push("in") if $in.defined;
    @args.push("out") if $out.defined;
    
    @args.push("scale default") if $scale-default.defined;

    my @scale-args;
    @scale-args.push($scale-major) if $scale-major.defined;
    @scale-args.push($scale-minor) if $scale-major.defined and $scale-minor.defined;
    
    if @scale-args.elems > 0 {
        @args.push(sprintf("scale %s", @scale-args.join(",")));
    }
    
    if $rotate.defined {
        given $rotate {
            when $_ ~~ Bool and $_ == False { @args.push("norotate") }
            when * ~~ Real { @args.push("rotate by $rotate") }
            default { die "Error: Something went wrong." }
        }
    }

    @args.push(self!tweak-coordinate(:name("offset"), :coordinate($offset), :enable-nooffset));
    @args.push("left") if $left.defined;
    @args.push("right") if $right.defined;
    @args.push("center") if $center.defined;
    @args.push("autojustify") if $autojustify.defined;
    @args.push("add") if $add.defined;
    @args.push("autofreq") if $autofreq.defined;

    if $incr.defined and (not $start.defined and not $end.defined) {
        @args.push($incr) if $incr.defined;
    } else {
        if $start.defined and $incr.defined and $end.defined {
            @args.push(sprintf("%s, %s, %s", $start, $incr, $end));
        } elsif $start.defined and $incr.defined {
            @args.push(sprintf("%s, %s", $start, $incr));
        }
    }

    if @tics.elems > 0 {
        my @tic-args;
        for @tics -> $t {
            my @tmp;
            if $t<label>:exists {
                @tmp.push(sprintf("\"%s\"", $t<label>));
            }

            @tmp.push($t<pos>);
            if $t<level>:exists {
                @tmp.push($t<level>);
            }
            @tic-args.push(@tmp.join(" "));
        }
        @args.push(sprintf("(%s)", @tic-args.join(",")));
    }

    @args.push(sprintf("format \"%s\"", $format)) if $format.defined;
    @args.push(self!tweak-fontargs(:$font-name, :$font-size));

    @args.push($enhanced ?? "enhanced" !! "noenhanced") if $enhanced.defined;
    @args.push("numeric") if $numeric.defined;
    @args.push("timedate") if $timedate.defined;
    @args.push("geographic") if $geographic.defined;
    @args.push("rangelimited") if $rangelimited.defined;
    @args.push("textcolor " ~ $textcolor) if $textcolor.defined;
    @args.grep(* ne "").join(" ")
}

method xtics(:$axis, :$border, Bool :$mirror,
             :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, AnyTicsRotate :$rotate, AnyTicsOffset :$offset,
             :$left, :$right, :$center, :$autojustify,
             :$add,
             :$autofreq,
             :$incr,
             :$start, :$end,
             :@tics,
             :$format, :$font-name, :$font-size, Bool :$enhanced,
             :$numeric, :$timedate, :$geographic,
             :$rangelimited,
             :$textcolor, :&writer? = -> $msg { self.command: $msg }
            ) {
    &writer(sprintf("set xtics %s", self!anytics(:$axis, :$border, :$mirror,
                                                           :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, :$rotate, :$offset,
                                                           :$left, :$right, :$center, :$autojustify,
                                                           :$add,
                                                           :$autofreq,
                                                           :$incr,
                                                           :$start, :$end,
                                                           :@tics,
                                                           :$format, :$font-name, :$font-size, :$enhanced,
                                                           :$numeric, :$timedate, :$geographic,
                                                           :$rangelimited,
                                                           :$textcolor)));
}

method ytics(:$axis, :$border, Bool :$mirror,
             :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, AnyTicsRotate :$rotate, AnyTicsOffset :$offset,
             :$left, :$right, :$center, :$autojustify,
             :$add,
             :$autofreq,
             :$incr,
             :$start, :$end,
             :@tics,
             :$format, :$font-name, :$font-size, Bool :$enhanced,
             :$numeric, :$timedate, :$geographic,
             :$rangelimited,
             :$textcolor, :&writer? = -> $msg { self.command: $msg }
            ) {
    &writer(sprintf("set ytics %s", self!anytics(:$axis, :$border, :$mirror,
                                                 :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, :$rotate, :$offset,
                                                 :$left, :$right, :$center, :$autojustify,
                                                 :$add,
                                                 :$autofreq,
                                                 :$incr,
                                                 :$start, :$end,
                                                 :@tics,
                                                 :$format, :$font-name, :$font-size, :$enhanced,
                                                 :$numeric, :$timedate, :$geographic,
                                                 :$rangelimited,
                                                 :$textcolor)));
}

method ztics(:$axis, :$border, Bool :$mirror,
             :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, AnyTicsRotate :$rotate, AnyTicsOffset :$offset,
             :$left, :$right, :$center, :$autojustify,
             :$add,
             :$autofreq,
             :$incr,
             :$start, :$end,
             :@tics,
             :$format, :$font-name, :$font-size, Bool :$enhanced,
             :$numeric, :$timedate, :$geographic,
             :$rangelimited,
             :$textcolor, :&writer? = -> $msg { self.command: $msg }
            ) {
    &writer(sprintf("set ztics %s", self!anytics(:$axis, :$border, :$mirror,
                                                 :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, :$rotate, :$offset,
                                                 :$left, :$right, :$center, :$autojustify,
                                                 :$add,
                                                 :$autofreq,
                                                 :$incr,
                                                 :$start, :$end,
                                                 :@tics,
                                                 :$format, :$font-name, :$font-size, :$enhanced,
                                                 :$numeric, :$timedate, :$geographic,
                                                 :$rangelimited,
                                                 :$textcolor)));
}

method x2tics(:$axis, :$border, Bool :$mirror,
              :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, AnyTicsRotate :$rotate, AnyTicsOffset :$offset,
              :$left, :$right, :$center, :$autojustify,
              :$add,
              :$autofreq,
              :$incr,
              :$start, :$end,
              :@tics,
              :$format, :$font-name, :$font-size, Bool :$enhanced,
              :$numeric, :$timedate, :$geographic,
              :$rangelimited,
              :$textcolor, :&writer? = -> $msg { self.command: $msg }
             ) {
    &writer(sprintf("set x2tics %s", self!anytics(:$axis, :$border, :$mirror,
                                                  :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, :$rotate, :$offset,
                                                  :$left, :$right, :$center, :$autojustify,
                                                  :$add,
                                                  :$autofreq,
                                                  :$incr,
                                                  :$start, :$end,
                                                  :@tics,
                                                  :$format, :$font-name, :$font-size, :$enhanced,
                                                  :$numeric, :$timedate, :$geographic,
                                                  :$rangelimited,
                                                  :$textcolor)));
}

method y2tics(:$axis, :$border, Bool :$mirror,
              :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, AnyTicsRotate :$rotate, AnyTicsOffset :$offset,
              :$left, :$right, :$center, :$autojustify,
              :$add,
              :$autofreq,
              :$incr,
              :$start, :$end,
              :@tics,
              :$format, :$font-name, :$font-size, Bool :$enhanced,
              :$numeric, :$timedate, :$geographic,
              :$rangelimited,
              :$textcolor, :&writer? = -> $msg { self.command: $msg }
             ) {
    &writer(sprintf("set y2tics %s", self!anytics(:$axis, :$border, :$mirror,
                                                  :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, :$rotate, :$offset,
                                                  :$left, :$right, :$center, :$autojustify,
                                                  :$add,
                                                  :$autofreq,
                                                  :$incr,
                                                  :$start, :$end,
                                                  :@tics,
                                                  :$format, :$font-name, :$font-size, :$enhanced,
                                                  :$numeric, :$timedate, :$geographic,
                                                  :$rangelimited,
                                                  :$textcolor)));
}

method cbtics(:$axis, :$border, Bool :$mirror,
              :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, AnyTicsRotate :$rotate, AnyTicsOffset :$offset,
              :$left, :$right, :$center, :$autojustify,
              :$add,
              :$autofreq,
              :$incr,
              :$start, :$end,
              :@tics,
              :$format, :$font-name, :$font-size, Bool :$enhanced,
              :$numeric, :$timedate, :$geographic,
              :$rangelimited,
              :$textcolor, :&writer? = -> $msg { self.command: $msg }
             ) {
    &writer(sprintf("set cbtics %s", self!anytics(:$axis, :$border, :$mirror,
                                                  :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, :$rotate, :$offset,
                                                  :$left, :$right, :$center, :$autojustify,
                                                  :$add,
                                                  :$autofreq,
                                                  :$incr,
                                                  :$start, :$end,
                                                  :@tics,
                                                  :$format, :$font-name, :$font-size, :$enhanced,
                                                  :$numeric, :$timedate, :$geographic,
                                                  :$rangelimited,
                                                  :$textcolor)));
}

my subset LegendMax of Cool where { if not $_.defined { True } else { $_ eq "auto" or $_ ~~ Real } };

method legend(:$on, :$off, :$default, :$inside, :$outside, :$lmargin, :$rmargin, :$tmargin, :$bmargin,
              :$at,
              :$left, :$right, :$center, :$top, :$bottom,
              :$vertical, :$horizontal, :$Left, :$Right,
              Bool :$opaque, Bool :$reverse, Bool :$invert,
              :$samplen, :$spacing, :$width, :$height,
              :$autotitle, :$columnheader, :$title, :$font-name, :$font-size, :$textcolor,
              Bool :$box, :$linestyle, :$linetype, :$linewidth,
              LegendMax :$maxcols, LegendMax :$maxrows, :&writer? = -> $msg { self.command: $msg }) {
    my @args;
    @args.push("on") if $on.defined;
    @args.push("off") if $off.defined;
    @args.push("default") if $default.defined;
    @args.push("inside") if $inside.defined;
    @args.push("outside") if $outside.defined;
    @args.push("lmargin") if $lmargin.defined;
    @args.push("rmargin") if $rmargin.defined;
    @args.push("tmargin") if $tmargin.defined;
    @args.push("bmargin") if $bmargin.defined;
    @args.push(self!tweak-coordinate(:name("at"), :coordinate($at)));
    @args.push("left") if $left.defined;
    @args.push("right") if $right.defined;
    @args.push("top") if $top.defined;
    @args.push("bottom") if $bottom.defined;
    @args.push("center") if $center.defined;
    @args.push("vertical") if $vertical.defined;
    @args.push("horizontal") if $horizontal.defined;
    @args.push("Left") if $Left.defined;
    @args.push("Right") if $Right.defined;
    @args.push($opaque ?? "opaque" !! "noopaque") if $opaque.defined;
    @args.push($reverse ?? "reverse" !! "noreverse") if $reverse.defined;
    @args.push($invert ?? "invert" !! "noinvert") if $invert.defined;
    @args.push("samplen " ~ $samplen) if $samplen.defined;
    @args.push("spacing " ~ $spacing) if $spacing.defined;
    @args.push("width " ~ $width) if $width.defined;
    @args.push("height " ~ $height) if $height.defined;
    @args.push("autotitle") if $autotitle.defined;
    @args.push("columnheader") if $autotitle.defined and $columnheader.defined;
    @args.push(sprintf("title \"%s\"", $title)) if $title.defined;
    
    @args.push(self!tweak-fontargs(:$font-name, :$font-size));
    @args.push("textcolor " ~ $textcolor) if $textcolor.defined;
    @args.push($box ?? "box" !! "nobox") if $box.defined;
    @args.push("linestyle " ~ $linestyle) if $box.defined and $linestyle.defined;
    @args.push("linetype " ~ $linetype) if $box.defined and $linetype.defined;
    @args.push("linewidth " ~ $linewidth) if $box.defined and $linewidth.defined;
    if $maxcols.defined {
        @args.push("maxcols " ~ $maxcols) if $maxcols ~~ Real;
        @args.push("maxcols auto") if $maxcols eq "auto";
    }

    if $maxrows.defined {
        @args.push("maxrows " ~ $maxrows) if $maxrows ~~ Real;
        @args.push("maxrows auto") if $maxrows eq "auto";
    }

    &writer(sprintf("set key %s", @args.grep(* ne "").join(" ")));
}

method border(:$integer, :$front, :$back, :$behind,
              :lw(:$linewidth), :ls(:$linestyle), :lt(:$linetype), :&writer? = -> $msg { self.command: $msg }) {
    my @args;
    @args.push($integer) if $integer.defined;
    @args.push("front") if $front.defined;
    @args.push("back") if $back.defined;
    @args.push("behind") if $behind.defined;
    @args.push("linewidth " ~ $linewidth) if $linewidth.defined;
    @args.push("linestyle " ~ $linestyle) if $linestyle.defined;
    @args.push("linetype " ~ $linetype) if $linetype.defined;

    &writer(sprintf("set border %s", @args.grep(* ne "").join(" ")));
}

method grid(Bool :$xtics, TrueOnly :$mxtics, Bool :$ytics, TrueOnly :$mytics, Bool :$ztics, TrueOnly :$mztics, Bool :$x2tics, TrueOnly :$mx2tics, Bool :$y2tics, TrueOnly :$my2tics, Bool :$cbtics, TrueOnly :$mcbtics,
            :$polar, :$layerdefault, :$front, :$back,
            :ls(:@linestyle), :lt(:@linetype), :lw(:@linewidth), :&writer? = -> $msg { self.command: $msg }) {
    my @args;
    @args.push($xtics ?? "xtics" !! "noxtics") if $xtics.defined;
    @args.push("mxtics") if $mxtics.defined;
    @args.push($ytics ?? "ytics" !! "noytics") if $ytics.defined;
    @args.push("mytics") if $mytics.defined;
    @args.push($ztics ?? "ztics" !! "noztics") if $ztics.defined;
    @args.push("mztics") if $mztics.defined;

    @args.push($x2tics ?? "x2tics" !! "nox2tics") if $x2tics.defined;
    @args.push("mx2tics") if $mx2tics.defined;
    @args.push($y2tics ?? "y2tics" !! "noy2tics") if $y2tics.defined;
    @args.push("my2tics") if $my2tics.defined;
    @args.push($cbtics ?? "cbtics" !! "nocbtics") if $cbtics.defined;
    @args.push("mcbtics") if $mcbtics.defined;

    @args.push("polar " ~ $polar) if $polar.defined;
    @args.push("layerdefault") if $layerdefault.defined;
    @args.push("front") if $front.defined;
    @args.push("back") if $back.defined;

    @args.push("linestyle " ~ @linestyle[0]) if @linestyle.elems >= 1;
    @args.push("linetype " ~ @linetype[0]) if @linetype.elems >= 1;
    @args.push("linewidth " ~ @linewidth[0]) if @linewidth.elems >= 1;

    @args.push(",") if @linestyle.elems|@linetype.elems|@linewidth.elems == 2;
    @args.push("linestyle " ~ @linestyle[1]) if @linestyle.elems == 2;
    @args.push("linetype " ~ @linetype[1]) if @linetype.elems == 2;
    @args.push("linewidth " ~ @linewidth[1]) if @linewidth.elems == 2;

    &writer(sprintf("set grid %s", @args.grep(* ne "").join(" ")));
}

method timestamp(:$format, :$top, :$bottom, Bool :$rotate,
                 :$offset, :$font-name, :$font-size, :$textcolor, :&writer? = -> $msg { self.command: $msg }) {
    my @args;
    @args.push(sprintf("\"%s\"", $format)) if $format.defined;
    @args.push("top") if $top.defined;
    @args.push("bottom") if $bottom.defined;
    @args.push($rotate ?? "rotate" !! "norotate") if $rotate.defined;

    @args.push(self!tweak-coordinate(:name("offset"), :coordinate($offset))) if $offset.defined;
    @args.push(self!tweak-fontargs(:$font-name, :$font-size));

    @args.push("textcolor " ~ $textcolor) if $textcolor.defined;

    &writer(sprintf("set timestamp %s", @args.grep(* ne "").join(" ")));
}

method !anyobject(:$front, :$back, :$behind, Bool :$clip, :$fillcolor, :$fillstyle,
                  :$default, :$linewidth, :$dashtype, :&writer? = -> $msg { self.command: $msg }) {

    my @args;
    @args.push("front") if $front.defined;
    @args.push("back") if $back.defined;
    @args.push("behind") if $behind.defined;
    @args.push($clip ?? "clip" !! "noclip") if $clip.defined;
    @args.push("fillcolor " ~ $fillcolor) if $fillcolor.defined;
    @args.push("fillstyle " ~ $fillstyle) if $fillstyle.defined;
    @args.push("default") if $default.defined;
    @args.push("linewidth " ~ $linewidth) if $linewidth.defined;
    @args.push("dashtype " ~ $dashtype) if $dashtype.defined;
    @args.grep(* ne "").join(" ");
}

multi method rectangle(:$index!, :$from, :$to,
                       :$front, :$back, :$behind, Bool :$clip, :$fillcolor, :$fillstyle,
                       :$default, :$linewidth, :$dashtype, :&writer? = -> $msg { self.command: $msg }) {

    my @args;
    @args.push(self!tweak-coordinate(:name("from"), :coordinate($from)));
    @args.push(self!tweak-coordinate(:name("to"), :coordinate($to)));
    @args.push(self!anyobject(:$front, :$back, :$behind, :$clip, :$fillcolor, :$fillstyle,
                              :$default, :$linewidth, :$dashtype));
    &writer(sprintf("set object %d rectangle %s", $index, @args.grep(* ne "").join(" ")))
}

multi method rectangle(:$index, :$from, :$rto,
                       :$front, :$back, :$behind, Bool :$clip, :$fillcolor, :$fillstyle,
                       :$default, :$linewidth, :$dashtype, :&writer? = -> $msg { self.command: $msg }) {

    my @args;
    @args.push(self!tweak-coordinate(:name("from"), :coordinate($from)));
    @args.push(self!tweak-coordinate(:name("rto"), :coordinate($rto)));
    @args.push(self!anyobject(:$front, :$back, :$behind, :$clip, :$fillcolor, :$fillstyle,
                              :$default, :$linewidth, :$dashtype));
    &writer(sprintf("set object %d rectangle %s", $index, @args.grep(* ne "").join(" ")));
}

method ellipse(:$index, :center(:$at), :$w!, :$h!,
               :$front, :$back, :$behind, Bool :$clip, :$fillcolor, :$fillstyle,
               :$default, :$linewidth, :$dashtype, :&writer? = -> $msg { self.command: $msg }) {
    my @args;
    @args.push(self!tweak-coordinate(:name("at"), :coordinate($at)));
    @args.push(sprintf("size %s,%s", $w, $h));
    @args.push(self!anyobject(:$front, :$back, :$behind, :$clip, :$fillcolor, :$fillstyle,
                              :$default, :$linewidth, :$dashtype));
    &writer(sprintf("set object %d ellipse %s", $index, @args.grep(* ne "").join(" ")));
}

method circle(:$index, :center(:$at), :$radius!,
              :$front, :$back, :$behind, Bool :$clip, :$fillcolor, :$fillstyle,
              :$default, :$linewidth, :$dashtype, :&writer? = -> $msg { self.command: $msg }) {
    my @args;
    @args.push(self!tweak-coordinate(:name("at"), :coordinate($at)));
    @args.push(sprintf("size %s", $radius));
    @args.push(self!anyobject(:$front, :$back, :$behind, :$clip, :$fillcolor, :$fillstyle,
                              :$default, :$linewidth, :$dashtype));
    
    &writer(sprintf("set object %d circle %s", $index, @args.grep(* ne "").join(" ")));
}

method polygon(:$index, :$from, :@to,
               :$front, :$back, :$behind, Bool :$clip, :$fillcolor, :$fillstyle,
               :$default, :$linewidth, :$dashtype, :&writer? = -> $msg { self.command: $msg }) {
    my @args;
    @args.push(self!tweak-coordinate(:name("from"), :coordinate($from)));
    @args.push(@to.map(-> $c { self!tweak-coordinate(:coordinate($c), :name("to")) }).join(" "));
    @args.push(self!anyobject(:$front, :$back, :$behind, :$clip, :$fillcolor, :$fillstyle,
                              :$default, :$linewidth, :$dashtype));
    &writer(sprintf("set object %d polygon %s", $index, @args.grep(* ne "").join(" ")));
}

method title(:$text, :$offset, :$font-name, :$font-size, :tc(:$textcolor), :$colorspec, Bool :$enhanced, :&writer? = -> $msg { self.command: $msg }) {
    my @args;
    
    @args.push(sprintf("\"%s\"", $text));
    @args.push(self!tweak-coordinate(:name("offset"), :coordinate($offset)));
    @args.push(self!tweak-fontargs(:$font-name, :$font-size));
    @args.push("textcolor " ~ $textcolor) if $textcolor.defined;
    @args.push("colorspec " ~ $colorspec) if $colorspec.defined;
    @args.push($enhanced ?? "enhanced" !! "noenhanced") if $enhanced.defined;

    &writer(sprintf("set title %s", @args.grep(* ne "").join(" ")));
}

multi method arrow(:$tag, :$from, :$to, Bool :$head, :$backhead, :$heads,
             :$head-length, :$head-angle, :$back-angle,
             :$filled, :$empty, :$border,
             :$front, :$back,
             :ls(:$linestyle), :lt(:$linetype), :lw(:$linewidth), :lc(:$linecolor), :dt(:$dashtype), :&writer? = -> $msg { self.command: $msg }
            ) {
    my @args;

    @args.push($tag) if $tag.defined;
    @args.push(self!tweak-coordinate(:name("from"), :coordinate($from)));
    @args.push(self!tweak-coordinate(:name("to"), :coordinate($to)));
    @args.push($head ?? "head" !! "nohead") if $head.defined;
    @args.push("backhead") if $backhead.defined;
    @args.push("heads") if $heads.defined;
    if $head-length.defined and $head-angle.defined {
        if $back-angle.defined {
            @args.push(sprintf("size %s", ($head-length, $head-angle, $back-angle).join(",")));
        } else {
            @args.push(sprintf("size %s", ($head-length, $head-angle).join(",")));
        }
    }

    @args.push($filled ?? "filled" !! "nofilled") if $filled.defined;
    @args.push("empty") if $empty.defined;
    @args.push("border") if $border.defined;
    @args.push("front") if $front.defined;
    @args.push("back") if $back.defined;
    @args.push("linestyle " ~ $linestyle) if $linestyle.defined;
    @args.push("linetype " ~ $linetype) if $linetype.defined;
    @args.push("linewidth " ~ $linewidth) if $linewidth.defined;
    @args.push("linecolor " ~ $linecolor) if $linecolor.defined;
    @args.push("dashtype " ~ $dashtype) if $dashtype.defined;

    &writer(sprintf("set arrow %s", @args.grep(* ne "").join(" ")));
}

multi method arrow(:$tag, :$from, :$rto, Bool :$head, :$backhead, :$heads,
             :$head-length, :$head-angle, :$back-angle,
             :$filled, :$empty, :$border,
             :$front, :$back,
             :ls(:$linestyle), :lt(:$linetype), :lw(:$linewidth), :lc(:$linecolor), :dt(:$dashtype), :&writer? = -> $msg { self.command: $msg }
            ) {
    my @args;

    @args.push($tag) if $tag.defined;
    @args.push(self!tweak-coordinate(:name("from"), :coordinate($from)));
    @args.push(self!tweak-coordinate(:name("rto"), :coordinate($rto)));
    @args.push($head ?? "head" !! "nohead") if $head.defined;
    @args.push("backhead") if $backhead.defined;
    @args.push("heads") if $heads.defined;
    if $head-length.defined and $head-angle.defined {
        if $back-angle.defined {
            @args.push(sprintf("size %s", ($head-length, $head-angle, $back-angle).join(",")));
        } else {
            @args.push(sprintf("size %s", ($head-length, $head-angle).join(",")));
        }
    }

    @args.push($filled ?? "filled" !! "nofilled") if $filled.defined;
    @args.push("empty") if $empty.defined;
    @args.push("border") if $border.defined;
    @args.push("front") if $front.defined;
    @args.push("back") if $back.defined;
    @args.push("linestyle " ~ $linestyle) if $linestyle.defined;
    @args.push("linetype " ~ $linetype) if $linetype.defined;
    @args.push("linewidth " ~ $linewidth) if $linewidth.defined;
    @args.push("linecolor " ~ $linecolor) if $linecolor.defined;
    @args.push("dashtype " ~ $dashtype) if $dashtype.defined;

    &writer(sprintf("set arrow %s", @args.grep(* ne "").join(" ")));
}

method multiplot(:$title, :$font-name, :$font-size, Bool :$enhanced, :@layout, :$rowsfirst, :$columnsfirst,
                 :$downwards, :$upwards, :$scale, :$offset, :$margins,
                 :$spacing, :&writer = -> $msg { self.command: $msg }) {
    my @args;

    @args.push(sprintf("title \"%s\"", $title)) if $title.defined;
    @args.push(self!tweak-fontargs(:$font-name, :$font-size));
    @args.push($enhanced ?? "enhanced" !! "noenhanced") if $enhanced.defined;
    @args.push("layout " ~ @layout.join(",")) if @layout.elems > 0;
    @args.push("rowsfirst") if $rowsfirst.defined;
    @args.push("columnsfirst") if $columnsfirst.defined;
    @args.push("downwards") if $downwards.defined;
    @args.push("upwards") if $upwards.defined;
    @args.push("scale " ~ $scale.join(",")) if $scale.defined;
    @args.push(self!tweak-coordinate(:name("offset"), :coordinate($offset)));
    @args.push("margins " ~ $margins.join(",")) if $margins.elems == 4;
    @args.push("spacing " ~ $spacing.join(",")) if $spacing.defined;

    &writer(sprintf("set multiplot %s", @args.grep(* ne "").join(" ")));
}

method dispose {
    self.command: "exit";
}

method command(Str $command) {
    try sink await $!gnuplot.say: $command;

    if $!debug {
        sleep .5 unless @!msg-pool;
        $*ERR.print: $command ~ "\n"; # for IO::Capture::Simple
        $*ERR.print: @!msg-pool.join;
        @!msg-pool = ();
    }
}

=begin pod

=head1 NAME

Chart::Gnuplot - A Perl 6 bindings for gnuplot

=head1 SYNOPSIS

=head3 SOURCE

    use Chart::Gnuplot;

    my $gnu = Chart::Gnuplot.new(:terminal("png"), :filename("synopsis.png"));
    $gnu.title(:text("sin(x) curve"));
    $gnu.plot(:function('sin(x)'));

=head3 OUTPUT
    
=begin para

    <img src="synopsis.png" alt="sin(x)">

=end para

=head1 DESCRIPTION

Chart::Gnuplot is a Perl 6 naive bindings for gnuplot. Chart::Gnuplot runs C<gnuplot> using C<Proc::Async> and enables you to plot chart or graph with Perl6ish interface.

=head2 METHODS

=head3 terminal

Defined as:

        method terminal($terminal)

Tells gnuplot what kind of output to generate.

=head3 plot

Defined as:

        multi method plot(
                :$title, :$ignore, :@range, :@vertices!,
                :@using,
                Str :$style, :ls(:$linestyle), :lt(:$linetype), :lw(:$linewidth), :lc(:$linecolor),
                :$pointtype, :$pointsize, :$fill, FalseOnly :$hidden3d, FalseOnly :$contours,
                FalseOnly :$surface, :$palette,
                :&writer? = -> $msg { self.command: $msg }
        )

        multi method plot(
              :$title, :$ignore, :@range, :$function!,
              Str :$style, :ls(:$linestyle), :lt(:$linetype), :lw(:$linewidth), :lc(:$linecolor),
              :$pointtype, :$pointsize, :$fill, FalseOnly :$hidden3d, FalseOnly :$contours,
              FalseOnly :$surface, :$palette,
              :&writer? = -> $msg { self.command: $msg }
        )

Draws a 2-dimensional plot.

=head3 splot

Defined as:

        multi method splot(
              :@range,
              :@vertices!,
              :$binary, :$matrix, :$index, :$every,
              :$title, :$style, :ls(:$linestyle), :lt(:$linetype), :lw(:$linewidth), :lc(:$linecolor),
              :$pointtype, :$pointsize, :$fill, FalseOnly :$hidden3d, FalseOnly :$contours,
              FalseOnly :$surface, :$palette, :&writer? = -> $msg { self.command: $msg }
        )

        multi method splot(
              :@range,
              :$function!,
              :$title, :$style, :ls(:$linestyle), :lt(:$linetype), :lw(:$linewidth), :lc(:$linecolor),
              :$pointtype, :$pointsize, :$fill, FalseOnly :$hidden3d, FalseOnly :$contours,
              FalseOnly :$surface, :$palette, :&writer? = -> $msg { self.command: $msg }
        )

Draws a 3-dimensional plot.

=head3 label

Defined as:

        method label(
               :$tag, :$label-text, :$at, :$left, :$center, :$right,
               LabelRotate :$rotate, :$font-name, :$font-size, FalseOnly :$enhanced,
               :$front, :$back, :$textcolor, FalseOnly :$point, :$line-type, :$point-type, :$point-size, :$offset,
               :$boxed, :$hypertext, :&writer? = -> $msg { self.command: $msg }
        )

Places the text string at the corresponding 2D or 3D position.

=head3 xlabel

Defined as:

       method xlabel(
              Str :$label, :$offset, :$font-name, :$font-size, :$textcolor,
              Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = -> $msg { self.command: $msg }
       )

Sets the x-axis label.

=head3 ylabel

Defined as:

       method ylabel(
              Str :$label, :$offset, :$font-name, :$font-size, :$textcolor,
              Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = -> $msg { self.command: $msg }
       )

Sets the y-axis label.

=head3 zlabel

Defined as:

       method zlabel(
              Str :$label, :$offset, :$font-name, :$font-size, :$textcolor,
              Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = -> $msg { self.command: $msg }
       )

Sets the z-axis label.

=head3 x2label

Defined as:

       method x2label(
              Str :$label, :$offset, :$font-name, :$font-size, :$textcolor,
              Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = -> $msg { self.command: $msg }
       )

Sets the x2-axis label.

=head3 y2label

Defined as:

       method y2label(
              Str :$label, :$offset, :$font-name, :$font-size, :$textcolor,
              Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = -> $msg { self.command: $msg }
       )

Sets the y2-axis label.

=head3 cblabel

Defined as:

       method cblabel(
              Str :$label, :$offset, :$font-name, :$font-size, :$textcolor,
              Bool :$enhanced, AnyLabelRotate :$rotate, :&writer? = -> $msg { self.command: $msg }
       )

Sets the cb-axis label.

=head3 xrange

Defined as:

        multi method xrange(
              :$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend,
              :&writer? = -> $msg { self.command: $msg }
        )

        multi method xrange(:$restore, :&writer? = -> $msg { self.command: $msg })

Sets the horizontal range that will be displayed.

=head3 yrange

Defined as:

        multi method yrange(
              :$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend,
              :&writer? = -> $msg { self.command: $msg }
        )

        multi method yrange(:$restore, :&writer? = -> $msg { self.command: $msg })

Sets the vertical range that will be displayed.

=head3 zrange

Defined as:

        multi method zrange(
              :$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend,
              :&writer? = -> $msg { self.command: $msg }
        )

        multi method zrange(:$restore, :&writer? = -> $msg { self.command: $msg })

Sets the range that will be displayed on the z axis.

=head3 x2range

Defined as:

        multi method x2range(
              :$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend,
              :&writer? = -> $msg { self.command: $msg }
        )

        multi method x2range(:$restore, :&writer? = -> $msg { self.command: $msg })

Sets the range that will be displayed on the x2 axis.

=head3 y2range

Defined as:

        multi method y2range(
              :$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend,
              :&writer? = -> $msg { self.command: $msg }
        )

        multi method y2range(:$restore, :&writer? = -> $msg { self.command: $msg })

Sets the range that will be displayed on the y2 axis.

=head3 cbrange

Defined as:

        multi method cbrange(
              :$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend,
              :&writer? = -> $msg { self.command: $msg }
        )

        multi method cbrange(:$restore, :&writer? = -> $msg { self.command: $msg })

Sets the range of values which are colored.

=head3 rrange

Defined as:

        multi method rrange(
              :$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend,
              :&writer? = -> $msg { self.command: $msg }
        )

        multi method rrange(:$restore, :&writer? = -> $msg { self.command: $msg })

Sets the range that will be displayed on the r axis.

=head3 trange

Defined as:

        multi method trange(
              :$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend,
              :&writer? = -> $msg { self.command: $msg }
        )

        multi method trange(:$restore, :&writer? = -> $msg { self.command: $msg })

Sets the parametric range used to compute x and y values when in parametric or polar modes.

=head3 urange

Defined as:

        multi method urange(
              :$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend,
              :&writer? = -> $msg { self.command: $msg }
        )

        multi method urange(:$restore, :&writer? = -> $msg { self.command: $msg })

Set the parametric ranges used to compute x, y, and z values when in splot parametric mode.

=head3 vrange

Defined as:

        multi method vrange(
              :$min, :$max, Bool :$reverse, Bool :$writeback, Bool :$extend,
              :&writer? = -> $msg { self.command: $msg }
        )

        multi method vrange(:$restore, :&writer? = -> $msg { self.command: $msg })

Set the parametric ranges used to compute x, y, and z values when in splot parametric mode.

=head3 xtics

Defined as:

        method xtics(
               :$axis, :$border, Bool :$mirror,
               :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, AnyTicsRotate :$rotate, AnyTicsOffset :$offset,
               :$left, :$right, :$center, :$autojustify,
               :$add,
               :$autofreq,
               :$incr,
               :$start, :$end,
               :@tics,
               :$format, :$font-name, :$font-size, Bool :$enhanced,
               :$numeric, :$timedate, :$geographic,
               :$rangelimited,
               :$textcolor, :&writer? = -> $msg { self.command: $msg }
        )

Controls the major (labeled) tics on the x axis.

=head3 ytics

Defined as:

        method ytics(
               :$axis, :$border, Bool :$mirror,
               :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, AnyTicsRotate :$rotate, AnyTicsOffset :$offset,
               :$left, :$right, :$center, :$autojustify,
               :$add,
               :$autofreq,
               :$incr,
               :$start, :$end,
               :@tics,
               :$format, :$font-name, :$font-size, Bool :$enhanced,
               :$numeric, :$timedate, :$geographic,
               :$rangelimited,
               :$textcolor, :&writer? = -> $msg { self.command: $msg }
        )

Controls the major (labeled) tics on the y axis.

=head3 ztics

Defined as:

        method ztics(
               :$axis, :$border, Bool :$mirror,
               :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, AnyTicsRotate :$rotate, AnyTicsOffset :$offset,
               :$left, :$right, :$center, :$autojustify,
               :$add,
               :$autofreq,
               :$incr,
               :$start, :$end,
               :@tics,
               :$format, :$font-name, :$font-size, Bool :$enhanced,
               :$numeric, :$timedate, :$geographic,
               :$rangelimited,
               :$textcolor, :&writer? = -> $msg { self.command: $msg }
        )

Controls the major (labeled) tics on the z axis.

=head3 x2tics

Defined as:

        method x2tics(
               :$axis, :$border, Bool :$mirror,
               :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, AnyTicsRotate :$rotate, AnyTicsOffset :$offset,
               :$left, :$right, :$center, :$autojustify,
               :$add,
               :$autofreq,
               :$incr,
               :$start, :$end,
               :@tics,
               :$format, :$font-name, :$font-size, Bool :$enhanced,
               :$numeric, :$timedate, :$geographic,
               :$rangelimited,
               :$textcolor, :&writer? = -> $msg { self.command: $msg }
        )

Controls the major (labeled) tics on the x2 axis.

=head3 y2tics

Defined as:

        method y2tics(
               :$axis, :$border, Bool :$mirror,
               :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, AnyTicsRotate :$rotate, AnyTicsOffset :$offset,
               :$left, :$right, :$center, :$autojustify,
               :$add,
               :$autofreq,
               :$incr,
               :$start, :$end,
               :@tics,
               :$format, :$font-name, :$font-size, Bool :$enhanced,
               :$numeric, :$timedate, :$geographic,
               :$rangelimited,
               :$textcolor, :&writer? = -> $msg { self.command: $msg }
        )

Controls the major (labeled) tics on the y2 axis.

=head3 cbtics

Defined as:

        method cbtics(
               :$axis, :$border, Bool :$mirror,
               :$in, :$out, :$scale-default, :$scale-major, :$scale-minor, AnyTicsRotate :$rotate, AnyTicsOffset :$offset,
               :$left, :$right, :$center, :$autojustify,
               :$add,
               :$autofreq,
               :$incr,
               :$start, :$end,
               :@tics,
               :$format, :$font-name, :$font-size, Bool :$enhanced,
               :$numeric, :$timedate, :$geographic,
               :$rangelimited,
               :$textcolor, :&writer? = -> $msg { self.command: $msg }
        )

Controls the major (labeled) tics on the color box axis.

=head3 legend

Defined as:

        method legend(
               :$on, :$off, :$default, :$inside, :$outside, :$lmargin, :$rmargin, :$tmargin, :$bmargin,
               :$at,
               :$left, :$right, :$center, :$top, :$bottom,
               :$vertical, :$horizontal, :$Left, :$Right,
               Bool :$opaque, Bool :$reverse, Bool :$invert,
               :$samplen, :$spacing, :$width, :$height,
               :$autotitle, :$columnheader, :$title, :$font-name, :$font-size, :$textcolor,
               Bool :$box, :$linestyle, :$linetype, :$linewidth,
               LegendMax :$maxcols, LegendMax :$maxrows, :&writer? = -> $msg { self.command: $msg }
        )

Enables a key (or legend) containing a title and a sample (line, point, box) for each plot in the graph.

=head3 border

Defined as:

        method border(
               :$integer, :$front, :$back, :$behind,
               :lw(:$linewidth), :ls(:$linestyle), :lt(:$linetype), :&writer? = -> $msg { self.command: $msg }
        )

Controls the display of the graph borders for the plot and splot commands.

=head3 grid

Defined as:

        method grid(
               Bool :$xtics, TrueOnly :$mxtics, Bool :$ytics, TrueOnly :$mytics, Bool :$ztics, TrueOnly :$mztics,
               Bool :$x2tics, TrueOnly :$mx2tics, Bool :$y2tics, TrueOnly :$my2tics, Bool :$cbtics, TrueOnly :$mcbtics,
               :$polar, :$layerdefault, :$front, :$back,
               :ls(:@linestyle), :lt(:@linetype), :lw(:@linewidth), :&writer? = -> $msg { self.command: $msg }
        )

Allows grid lines to be drawn on the plot.

=head3 timestamp

Defined as:

        method timestamp(
                :$format, :$top, :$bottom, Bool :$rotate,
                :$offset, :$font-name, :$font-size, :$textcolor, :&writer? = -> $msg { self.command: $msg }
        )

Places the time and date of the plot in the left margin.

=head3 rectangle

Defined as:

        multi method rectangle(
              :$index!, :$from, :$to,
              :$front, :$back, :$behind, Bool :$clip, :$fillcolor, :$fillstyle,
              :$default, :$linewidth, :$dashtype, :&writer? = -> $msg { self.command: $msg }
        )

        multi method rectangle(
              :$index, :$from, :$rto,
              :$front, :$back, :$behind, Bool :$clip, :$fillcolor, :$fillstyle,
              :$default, :$linewidth, :$dashtype, :&writer? = -> $msg { self.command: $msg }
        )

Defines a single rectangle which will appear in all subsequent 2D plot.
 
=head3 ellipse

Defined as:

        method ellipse(
               :$index, :center(:$at), :$w!, :$h!,
               :$front, :$back, :$behind, Bool :$clip, :$fillcolor, :$fillstyle,
               :$default, :$linewidth, :$dashtype, :&writer? = -> $msg { self.command: $msg }
        )

Defines a single ellipse which will appear in all subsequent 2D plot.

=head3 circle

Defined as:

        method circle(
               :$index, :center(:$at), :$radius!,
               :$front, :$back, :$behind, Bool :$clip, :$fillcolor, :$fillstyle,
               :$default, :$linewidth, :$dashtype, :&writer? = -> $msg { self.command: $msg }
        )

Defines a single circle which will appear in all subsequent 2D plot.

=head3 polygon

Defined as:

        method polygon(
               :$index, :$from, :@to,
               :$front, :$back, :$behind, Bool :$clip, :$fillcolor, :$fillstyle,
               :$default, :$linewidth, :$dashtype, :&writer? = -> $msg { self.command: $msg }
        )

Defines a single polygon which will appear in all subsequent 2D plot.

=head3 title

Defined as:

        method title(
               :$text, :$offset, :$font-name, :$font-size, :tc(:$textcolor), :$colorspec, Bool :$enhanced,
               :&writer? = -> $msg { self.command: $msg }
        )

Produces a plot title that is centered at the top of the plot.

=head3 arrow

Defined as:

        multi method arrow(
              :$tag, :$from, :$to, Bool :$head, :$backhead, :$heads,
              :$head-length, :$head-angle, :$back-angle,
              :$filled, :$empty, :$border,
              :$front, :$back,
              :ls(:$linestyle), :lt(:$linetype), :lw(:$linewidth), :lc(:$linecolor), :dt(:$dashtype), :&writer? = -> $msg { self.command: $msg }
        )

Places an arrow on a plot.

=head3 multiplot

Defined as:

        multi method arrow(
              :$tag, :$from, :$rto, Bool :$head, :$backhead, :$heads,
              :$head-length, :$head-angle, :$back-angle,
              :$filled, :$empty, :$border,
              :$front, :$back,
              :ls(:$linestyle), :lt(:$linetype), :lw(:$linewidth), :lc(:$linecolor), :dt(:$dashtype), :&writer? = -> $msg { self.command: $msg }
        )

Places gnuplot in the multiplot mode, in which several plots are placed next to each other on the same page or screen window.

=head3 command

Defined as:

        method command(Str $command)

Runs a given C<$command>. If there are no appropriate interfaces, this method will be a good alternative.

=head1 EXAMPLES

=head2 3D surface from a grid (matrix) of Z values

=head3 SOURCE

    use Chart::Gnuplot;

    my $gnu = Chart::Gnuplot.new(:terminal("png"), :filename("surface.dem.00.png"));
    $gnu.title(:text("3D surface from a grid (matrix) of Z values"));
    $gnu.xrange(:min(-0.5), :max(4.5));
    $gnu.yrange(:min(-0.5), :max(4.5));
    $gnu.grid;
    $gnu.command("set hidden3d");

    my @grid = (q:to/EOF/).split("\n", :skip-empty)>>.split(" ", :skip-empty);
    5 4 3 1 0
    2 2 0 0 1
    0 0 0 1 0
    0 0 0 2 3
    0 1 2 4 3
    EOF

    $gnu.splot(:vertices(@grid), :style("lines"), :title(False), :matrix);

=head3 OUTPUT
    
=begin para

    <img src="surface.dem.00.png" alt="3D surface from a grid (matrix) of Z values">

=end para

=head1 AUTHOR

titsuki <titsuki@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright 2017 titsuki

This library is free software; you can redistribute it and/or modify it under the GNU General Public License version 3.0.

=end pod
