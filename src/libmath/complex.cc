#define MATHLIB_IMPLEMENTATION

#include <iostream>
#include <math.h>
#include "mathlib.h"

using namespace std;
using namespace toast;

// division and sqrt algorithms from NR p.176 and p.948

complex complex::operator/ (const complex &z) const
{
    double den = norm2(z);
    return complex ((re*z.re+im*z.im)/den, (im*z.re-re*z.im)/den);
}

complex complex::operator/= (const complex& z)
{
    double den = norm2(z);
    double r = (re*z.re+im*z.im)/den;
    im = (im*z.re-re*z.im)/den;
    re = r;
    return *this;
}

MATHLIB complex sqrt (const complex& z)
{
    if (!z.re && !z.im) return complex(0.0, 0.0);
    double r, w, x = fabs (z.re), y = fabs (z.im);
    if (x >= y) {
	r = y/x;
	w = ::sqrt (x) * ::sqrt (0.5 * (1.0 + ::sqrt (1.0+r*r)));
    } else {
	r = x/y;
	w = ::sqrt (y) * ::sqrt (0.5 * (r + ::sqrt (1.0+r*r)));
    }
    if (z.re >= 0.0) return complex (w, z.im/(2.0*w));
    if (z.im >= 0.0) return complex (z.im/(2.0*w), w);
    return complex (-z.im/(2.0*w), -w);
}

complex pow (const complex& /*zb*/, const complex& /*ze*/)
{
    xERROR(Function not implemented!);
    return (complex(0,0));
}

complex pow (const complex& /*zb*/, double /*e*/)
{
    xERROR(Function not implemented!);
    return (complex(0,0));
}

ostream &operator<< (ostream &os, const toast::complex &z)
{
    os << '<' << z.re << ' ' << z.im << '>';
    return os;
}

istream &operator>> (istream& is, toast::complex& z)
{
    char c;
    for (;;) {
	is >> c;
	if (c == '<') break;
	if (c == ' ' || c == '\t' || c == '\n') continue;
	is.unget();
	is.setstate (ios::failbit);
	return is;
    }

    is >> z.re >> z.im;
    do { is >> c; } while (is.good() && c != '>');
    return is;
}
