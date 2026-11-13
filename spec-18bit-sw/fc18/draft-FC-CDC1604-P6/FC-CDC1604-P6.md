```
Network Working Group                                        W. Cazander
Request for Comments: XXXX                             Independent Spec
Category: Standards Track                                  November 2026
```

#      FC.CDC1604-P6: 6-Bit Base Cakepoint Slice for the FC18 Encoding

## Status of This Memo

   This document specifies a foundational character set standard for the
   FC18 encoding ecosystem, and requests discussion and suggestions for
   improvements.  Distribution of this memo is unlimited.

## Abstract

   This specification defines "FC.CDC1604-P6", the foundational 6-bit
   (64-value) cakepoint slice of the 18-bit FC18 character encoding
   architecture.  Designed as a modern replacement for Unicode, FC18
   organizes data around 18-bit word architectures and Four Corner
   pie-slice number systems.  FC.CDC1604-P6 provides the base 6-bit
   alphabet for small mainframe computers and serves as ASCII-like glue
   for 18-bit systems.

## Table of Contents

    1.  Introduction . . . . . . . . . . . . . . . . . . . . . . . . .  2
    2.  Conventions and Terminology  . . . . . . . . . . . . . . . . .  2
    3.  Architecture Overview  . . . . . . . . . . . . . . . . . . . .  2
       3.1.  Control Slice (NS00..NS09) . . . . . . . . . . . . . . .  3
       3.2.  Reverse Symbol Slice (NY27..NY01)  . . . . . . . . . . .  3
       3.3.  Primary Letter Slice (NX01..NX27)  . . . . . . . . . . .  3
    4.  FC.CDC1604-P6 Cakepoint Table  . . . . . . . . . . . . . . . .  3
    5.  Escape Sequence Hooks and Future RFCs  . . . . . . . . . . . .  6
    6.  Security Considerations  . . . . . . . . . . . . . . . . . . .  6
    7.  IANA Considerations  . . . . . . . . . . . . . . . . . . . . .  6

### 1.  Introduction

   "FC.CDC1604-P6" (Four Corner Control Data Character - Packed 6-bit)
   is the first specification in a series defining FC18, an 18-bit
   replacement for Unicode.  While the full FC18 address space spans 18
   bits (262,144 cakepoints), small mainframe computers and legacy
   word-oriented hardware require a compact 6-bit subset that fits
   three characters cleanly inside an 18-bit machine word.

   FC.CDC1604-P6 defines the first 64 word numbers (indices 0 through 63)
   of the China Four Corner method, structuring them into 27 pie-slice
   number systems "Packed" for MATH and BASIC letters.  This slice acts
   as fundamental ASCII glue for full 18-bit computing environments.

### 2.  Conventions and Terminology

   The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
   "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this
   document are to be interpreted as described in RFC 2119.

   Cakepoint:  An integer index within the FC18 character space.  In
      FC.CDC1604-P6, cakepoints range from 0 (0x00) to 63 (0x3F).
   Unicode Mapping:  The legacy Unicode code point assigned to each
      cakepoint for interoperability and rendering on existing systems.

### 3.  Architecture Overview

   The 64 cakepoints of FC.CDC1604-P6 are partitioned into three logical
   groups:

      [__NUL][_ESC6_X1][_ESC6_X2][_ESC6_X3] ‽¿?! <>[] (){}
      ~+-* ,.:; '"`^ =#$%
      |_\/ @ABC DEFG HIJK
      LMNO PQRS TUVW XYZ&

### 3.1.  Control Slice (NS00..NS09)

   Indices 0 through 9 define string termination, 6-bit escape triggers,
   argument separators, and 3-bit Pepper/Salt escape bit markers.

### 3.2.  Reverse Symbol Slice (NY27..NY01)

   Indices 10 through 36 define the second set of 27 number letters,
   ordered in descending numerical sequence from NY27 ('[') down to
   NY01 ('@').

### 3.3.  Primary Letter Slice (NX01..NX27)

   Indices 37 through 63 define the first set of 27 number letters,
   spanning the 26 Latin uppercase letters ('A' through 'Z') followed
   by the ampersand ('&') as the 27th letter of the Old English
   alphabet.

### 4.  FC.CDC1604-P6 Cakepoint Table

   The following table normatively defines all 64 cakepoints, their
   canonical enum identifiers, legacy Unicode code point mappings, and
   functional descriptions derived from the reference implementation
   (FCDotCDC1604DashP6.java).

     Idx | Oct | Enum Name               | Unicode | Glyph | Description
     ----+-----+-------------------------+---------+-------+-------------------------
     0  | 00  | NS00_NUL1_TERMINATOR    | U+0000  |  NUL  | String termination code
        |     |                         |         |       | (not a candy letter).
     1  | 01  | NS01_ESC3_X1            | U+0001  |  SOH  | Goto direct escaped
        |     |                         |         |       | control (seq of 3, X1).
     2  | 02  | NS02_ESC3_X2            | U+0002  |  STX  | Goto direct escaped
        |     |                         |         |       | control (seq of 3, X2).
     3  | 03  | NS03_ESC3_X3            | U+0003  |  ETX  | Goto direct escaped
        |     |                         |         |       | control (seq of 3, X3).
     4  | 04  | NS04_RAKA1_INTERROBANG  | U+203D  |   ‽   | End of argumented
        |     |                         |         |       | escape sequence prayer.
     5  | 05  | NS05_RAKA1_UPQUESTION   | U+00BF  |   ¿   | Next argument separator
        |     |                         |         |       | for escape sequences.
     6  | 06  | NS06_PEPPER3_QUESTION   | U+003F  |   ?   | Pepper mark 0; spices up
        |     |                         |         |       | escape sequences.
     7  | 07  | NS07_PEPPER3_EXCLAMATION| U+0021  |   !   | Pepper mark 1; spices up
        |     |                         |         |       | escape sequences.
     8  | 10  | NS08_SALT3_COMPARE_LEFT | U+003C  |   <   | Salt lexer token 0;
        |     |                         |         |       | sweats up escapes.
     9  | 11  | NS09_SALT3_COMPARE_RIGHT| U+003E  |   >   | Salt lexer token 1;
        |     |                         |         |       | sweats up escapes.
    10  | 12  | NY27_SQUARE_LEFT        | U+005B  |   [   | Second set number letter
        |     |                         |         |       | 27 (Square bracket L).
    11  | 13  | NY26_SQUARE_RIGHT       | U+005D  |   ]   | Second set number letter
        |     |                         |         |       | 26 (Square bracket R).
    12  | 14  | NY25_ROUND_LEFT         | U+0028  |   (   | Second set number letter
        |     |                         |         |       | 25 (Parenthesis L).
    13  | 15  | NY24_ROUND_RIGHT        | U+0029  |   )   | Second set number letter
        |     |                         |         |       | 24 (Parenthesis R).
    14  | 16  | NY23_CURLY_LEFT         | U+007B  |   {   | Second set number letter
        |     |                         |         |       | 23 (Curly brace L).
    15  | 17  | NY22_CURLY_RIGHT        | U+007D  |   }   | Second set number letter
        |     |                         |         |       | 22 (Curly brace R).
    16  | 20  | NY21_TILDE              | U+007E  |   ~   | Second set number letter
        |     |                         |         |       | 21 (Tilde).
    17  | 21  | NY20_PLUS               | U+002B  |   +   | Second set number letter
        |     |                         |         |       | 20 (Plus sign).
    18  | 22  | NY19_MINUS              | U+002D  |   -   | Second set number letter
        |     |                         |         |       | 19 (Minus/Hyphen).
    19  | 23  | NY18_ASTERISK           | U+002A  |   *   | Second set number letter
        |     |                         |         |       | 18 (Asterisk).
    20  | 24  | NY17_COMMA              | U+002C  |   ,   | Second set number letter
        |     |                         |         |       | 17 (Comma).
    21  | 25  | NY16_DOT                | U+002E  |   .   | Second set number letter
        |     |                         |         |       | 16 (Period/Dot).
    22  | 26  | NY15_COLON              | U+003A  |   :   | Second set number letter
        |     |                         |         |       | 15 (Colon).
    23  | 27  | NY14_SEMICOLON          | U+003B  |   ;   | Second set number letter
        |     |                         |         |       | 14 (Semicolon).
    24  | 30  | NY13_APOSTROPHE         | U+0027  |   '   | Second set number letter
        |     |                         |         |       | 13 (Apostrophe).
    25  | 31  | NY12_QUOTATION          | U+0022  |   "   | Second set number letter
        |     |                         |         |       | 12 (Quotation mark).
    26  | 32  | NY11_BACKTICK           | U+0060  |   `   | Second set number letter
        |     |                         |         |       | 11 (Grave/Backtick).
    27  | 33  | NY10_CARET              | U+005E  |   ^   | Second set number letter
        |     |                         |         |       | 10 (Circumflex/Caret).
    28  | 34  | NY09_EQUALS             | U+003D  |   =   | Second set number letter
        |     |                         |         |       | 09 (Equals sign).
    29  | 35  | NY08_HASH               | U+0023  |   #   | Second set number letter
        |     |                         |         |       | 08 (Number/Hash sign).
    30  | 36  | NY07_DOLLAR             | U+0024  |   $   | Second set number letter
        |     |                         |         |       | 07 (Dollar sign).
    31  | 37  | NY06_PERCENT            | U+0025  |   %   | Second set number letter
        |     |                         |         |       | 06 (Percent sign).
    32  | 40  | NY05_BAR_VERTICAL       | U+007C  |   |   | Second set number letter
        |     |                         |         |       | 05 (Vertical bar).
    33  | 41  | NY04_BAR_UNDER          | U+005F  |   _   | Second set number letter
        |     |                         |         |       | 04 (Underscore).
    34  | 42  | NY03_BAR_V_LEFT         | U+005C  |   \   | Second set number letter
        |     |                         |         |       | 03 (Reverse solidus).
    35  | 43  | NY02_BAR_V_RIGHT        | U+002F  |   /   | Second set number letter
        |     |                         |         |       | 02 (Solidus/Slash).
    36  | 44  | NY01_AT                 | U+0040  |   @   | Second set number letter
        |     |                         |         |       | 01 (Commercial at).
    37  | 45  | NX01_A                  | U+0041  |   A   | First set tone letter
        |     |                         |         |       | "one" (or 'a' w/ glue).
    38  | 46  | NX02_B                  | U+0042  |   B   | First set number letter 2.
    39  | 47  | NX03_C                  | U+0043  |   C   | First set number letter 3.
    40  | 50  | NX04_D                  | U+0044  |   D   | First set number letter 4.
    41  | 51  | NX05_E                  | U+0045  |   E   | First set number letter 5.
    42  | 52  | NX06_F                  | U+0046  |   F   | First set number letter 6.
    43  | 53  | NX07_G                  | U+0047  |   G   | First set number letter 7.
    44  | 54  | NX08_H                  | U+0048  |   H   | First set number letter 8.
    45  | 55  | NX09_I                  | U+0049  |   I   | First set number letter 9.
    46  | 56  | NX10_J                  | U+004A  |   J   | First set number letter 10.
    47  | 57  | NX11_K                  | U+004B  |   K   | First set number letter 11.
    48  | 60  | NX12_L                  | U+004C  |   L   | First set number letter 12.
    49  | 61  | NX13_M                  | U+004D  |   M   | First set number letter 13.
    50  | 62  | NX14_N                  | U+004E  |   N   | First set number letter 14.
    51  | 63  | NX15_O                  | U+004F  |   O   | First set number letter 15.
    52  | 64  | NX16_P                  | U+0050  |   P   | First set number letter 16.
    53  | 65  | NX17_Q                  | U+0051  |   Q   | First set number letter 17.
    54  | 66  | NX18_R                  | U+0052  |   R   | First set number letter 18.
    55  | 67  | NX19_S                  | U+0053  |   S   | First set number letter 19.
    56  | 70  | NX20_T                  | U+0054  |   T   | First set number letter 20.
    57  | 71  | NX21_U                  | U+0055  |   U   | First set number letter 21.
    58  | 72  | NX22_V                  | U+0056  |   V   | First set number letter 22.
    59  | 73  | NX23_W                  | U+0057  |   W   | First set number letter 23.
    60  | 74  | NX24_X                  | U+0058  |   X   | First set number letter 24.
    61  | 75  | NX25_Y                  | U+0059  |   Y   | First set number letter 25.
    62  | 76  | NX26_Z                  | U+005A  |   Z   | First set number letter 26.
    63  | 77  | NX27_AMP                | U+0026  |   &   | 27th letter at the end
        |     |                         |         |       | of Old English alphabet.

### 5. Escape Sequence Hooks and Future RFCs

While FC.CDC1604-P6 operates strictly within 6-bit boundaries
(0..63), it reserves control cakepoints NS01 through NS09 to bridge
into the full 18-bit FC18 cakepoint space:
*  NS01_ESC3_X1, NS02_ESC3_X2, and NS03_ESC3_X3 initiate 3-character
escape sequences on 6-bit systems.
*  NS04_RAKA1_INTERROBANG ('‽') and NS05_RAKA1_UPQUESTION ('¿')
delimit and separate arguments within structured escape sequences.
*  NS06_PEPPER3_QUESTION ('?') and NS07_PEPPER3_EXCLAMATION ('!')
encode 3-bit octal values (0..7) across 3-glyph Pepper sequences.
*  NS08_SALT3_COMPARE_LEFT ('<') and NS09_SALT3_COMPARE_RIGHT ('>')
encode 3-bit octal values (0..7) across 3-glyph Salt sequences.
The complete state machine, grammar, and expansion rules for
multi-byte and 18-bit escape sequences are out of scope for this
document and SHALL be defined in a subsequent FC18 Escape Sequence
RFC.

### 6. Security Considerations

Implementations MUST validate that incoming 6-bit cakepoint indices
fall strictly within the 0..63 range.  Unrecognized or malformed
escape sequences initiated by NS01..NS03 MUST NOT cause buffer
overruns when transitioning between 6-bit mainframe buffers and full
18-bit FC18 internal representations.

### 7. IANA Considerations

This memo includes no request to IANA.
