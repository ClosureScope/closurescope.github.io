#import "../../typst/web-math.typ": web-equation
#show math.equation: web-equation
#include "math-layout.typ"

Baseline $x$ end. Baseline $g_j$ end. Baseline $tanh$ end.

#math.equation(alt: "x with an overline plus y crossed out", block: true, $overline(x)+cancel(y)$)

#set math.equation(numbering: "(1)")
$ a=b $ <svg-first>
$ c=d $ <svg-second>
See @svg-first and @svg-second.

#set math.equation(numbering: none)
$ x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 + x^2 $
