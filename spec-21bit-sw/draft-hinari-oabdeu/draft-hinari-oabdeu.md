```
Network Working Group                                         A. Author
Request for Comments: XXXX                             Independent Spec
Category: Informational                                   November 2026
```

#            Hinari: Octal-Aligned Binary Data Encoding in Unicode

## Status of This Memo

   This document provides information for the Internet community.  It
   does not specify an Internet standard of any kind.  Distribution of
   this memo is unlimited.

## Abstract

   This specification defines "Hinari", a compact binary-to-text data
   encoding scheme utilizing Unicode code points from the Hebrew block
   (U+0590..U+05FF).  Hinari maps octal data in 3-bit, 6-bit, or 9-bit
   chunks per visual glyph cluster.  Code points are strictly ordered
   by ascending scalar value to preserve big-endian lexicographical
   sorting.

## Table of Contents

    1.  Introduction . . . . . . . . . . . . . . . . . . . . . . . . .  2
    2.  Conventions and Terminology  . . . . . . . . . . . . . . . . .  2
    3.  Code Point Alphabets . . . . . . . . . . . . . . . . . . . . .  2
        3.1.  Base Set (StrHinarī) . . . . . . . . . . . . . . . . . .  2
        3.2.  6-Bit Supplement (StrHinarīSupplement6)  . . . . . . . .  3
        3.3.  9-Bit Supplement (StrHinarīSupplement9)  . . . . . . . .  3
    4.  Encoding Variants  . . . . . . . . . . . . . . . . . . . . . .  3
        4.1.  Hinari-3 (3-Bit per Glyph) . . . . . . . . . . . . . . .  3
        4.2.  Hinari-6 (6-Bit per Glyph) . . . . . . . . . . . . . . .  4
        4.3.  Hinari-9 (9-Bit per Glyph) . . . . . . . . . . . . . . .  4
    5.  Lexicographical Sorting and Bit Alignment  . . . . . . . . . .  4
    6.  Reference Implementation (Pseudocode)  . . . . . . . . . . . .  5
    7.  Security Considerations  . . . . . . . . . . . . . . . . . . .  6
    8.  IANA Considerations  . . . . . . . . . . . . . . . . . . . . .  6

### 1.  Introduction

   Traditional hexadecimal encodings represent 4 bits per character,
   creating alignment friction with 3-bit octal boundaries, 6-bit
   base64 structures, and 9-bit or 18-bit word architectures.  Hinari
   solves this by pairing narrow-width Hebrew base letters with two
   distinct vertical tiers of combining diacritical marks (niqqud and
   cantillation marks).

   By combining one base letter with zero, one, or two combining marks,
   a single rendered glyph cluster encodes 1, 2, or 3 octal digits (3,
   6, or 9 bits) respectively.

### 2.  Conventions and Terminology

   The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
   "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this
   document are to be interpreted as described in RFC 2119.

   Octal Digit:  An integer value in the range 0 to 7 (3 bits).
   Glyph Cluster:  A sequence of 1 to 3 Unicode code points forming a
      single combined visual character.
   Big-Endian Order:  Most significant bits or octal digits appear
      first in the encoded stream.

### 3.  Code Point Alphabets

   All three alphabets consist of exactly 8 Unicode code points,
   mapping directly to octal values 0 through 7.

### 3.1.  Base Set (StrHinarī)

   The base set consists of 8 narrow Hebrew consonants and ligatures
   (General Category: Lo).  This set encodes the most significant 3
   bits of every glyph cluster.

      Octal | Binary | Code Point | Escaped  | Unicode Name
      ------+--------+------------+----------+------------------------
        0   |  000   |   U+05D3   |  \u05D3  | HEBREW LETTER DALET
        1   |  001   |   U+05D5   |  \u05D5  | HEBREW LETTER VAV
        2   |  010   |   U+05D6   |  \u05D6  | HEBREW LETTER ZAYIN
        3   |  011   |   U+05D9   |  \u05D9  | HEBREW LETTER YOD
        4   |  100   |   U+05E8   |  \u05E8  | HEBREW LETTER RESH
        5   |  101   |   U+05F0   |  \u05F0  | HEBREW LIGATURE YIDDISH DOUBLE VAV
        6   |  110   |   U+05F1   |  \u05F1  | HEBREW LIGATURE YIDDISH VAV YOD
        7   |  111   |   U+05F2   |  \u05F2  | HEBREW LIGATURE YIDDISH DOUBLE YOD

### 3.2.  6-Bit Supplement (StrHinarīSupplement6)

   The 6-bit supplement consists of 8 below-base combining marks
   (General Category: Mn, Canonical Combining Class: 10..22).

      Octal | Binary | Code Point | Escaped  | Unicode Name
      ------+--------+------------+----------+------------------------
        0   |  000   |   U+05B0   |  \u05B0  | HEBREW POINT SHEVA
        1   |  001   |   U+05B2   |  \u05B2  | HEBREW POINT HATAF PATAH
        2   |  010   |   U+05B3   |  \u05B3  | HEBREW POINT HATAF QAMATS
        3   |  011   |   U+05B5   |  \u05B5  | HEBREW POINT TSERE
        4   |  100   |   U+05B6   |  \u05B6  | HEBREW POINT SEGOL
        5   |  101   |   U+05B7   |  \u05B7  | HEBREW POINT PATAH
        6   |  110   |   U+05BB   |  \u05BB  | HEBREW POINT QUBUTS
        7   |  111   |   U+05BD   |  \u05BD  | HEBREW POINT METEG

### 3.3.  9-Bit Supplement (StrHinarīSupplement9)

   The 9-bit supplement consists of 8 above-base cantillation combining
   marks (General Category: Mn, Canonical Combining Class: 230).

      Octal | Binary | Code Point | Escaped  | Unicode Name
      ------+--------+------------+----------+------------------------
        0   |  000   |   U+0594   |  \u0594  | HEBREW ACCENT ZAQEF QATAN
        1   |  001   |   U+0595   |  \u0595  | HEBREW ACCENT ZAQEF GADOL
        2   |  010   |   U+0598   |  \u0598  | HEBREW ACCENT ZARQA
        3   |  011   |   U+059D   |  \u059D  | HEBREW ACCENT GERESH MUQDAM
        4   |  100   |   U+059E   |  \u059E  | HEBREW ACCENT GERSHAYIM
        5   |  101   |   U+059F   |  \u059F  | HEBREW ACCENT QARNEY PARA
        6   |  110   |   U+05A0   |  \u05A0  | HEBREW ACCENT TELISHA GEDOLA
        7   |  111   |   U+05A9   |  \u05A9  | HEBREW ACCENT TELISHA QETANA

### 4.  Encoding Variants

   An encoder MUST select one of the three variants below for a given
   stream.  Mixing variants within a single contiguous stream is NOT
   RECOMMENDED unless delimited externally.

### 4.1.  Hinari-3 (3-Bit per Glyph)

   Hinari-3 encodes 1 octal digit (3 bits) per glyph cluster using 1
   Unicode code point.

   o  Code point 1: Base Set [bits 2..0]

### 4.2.  Hinari-6 (6-Bit per Glyph)

   Hinari-6 encodes 2 octal digits (6 bits) per glyph cluster using 2
   Unicode code points in strict logical order.

*  Code point 1: Base Set [bits 5..3] (Most Significant Octal)
*  Code point 2: 6-Bit Supplement [bits 2..0] (Least Significant Octal)

### 4.3.  Hinari-9 (9-Bit per Glyph)

   Hinari-9 encodes 3 octal digits (9 bits) per glyph cluster using 3
   Unicode code points in strict logical order.

*  Code point 1: Base Set [bits 8..6] (Most Significant Octal)
*  Code point 2: 6-Bit Supplement [bits 5..3] (Middle Octal)
*  Code point 3: 9-Bit Supplement [bits 2..0] (Least Significant Octal)

### 5.  Lexicographical Sorting and Bit Alignment

   Within each individual alphabet set, code points are strictly
   ordered by ascending Unicode scalar value:

*  Base Set: U+05D3 < U+05D5 < U+05D6 < U+05D9 < U+05E8 < U+05F0 <
      U+05F1 < U+05F2
*  6-Bit Supplement: U+05B0 < U+05B2 < U+05B3 < U+05B5 < U+05B6 <
      U+05B7 < U+05BB < U+05BD
*  9-Bit Supplement: U+0594 < U+0595 < U+0598 < U+059D < U+059E <
      U+059F < U+05A0 < U+05A9

   Because glyph clusters are serialized from most significant octal
   digit to least significant octal digit (Base -> Supplement6 ->
   Supplement9), binary UTF-8, UTF-16, or UTF-32 code point comparisons
   on fixed-variant Hinari strings yield the exact same sort order as
   the underlying big-endian unsigned binary integers.

   When encoding arbitrary byte arrays whose total bit length is not
   evenly divisible by 3, 6, or 9, the encoder MUST right-pad the final
   incomplete bit group with zero bits (0) to reach the variant's bit
   width.  Decoders MUST discard trailing bits that do not form a full
   8-bit octet unless operating in raw bit-stream mode.

### 6.  Reference Implementation (Pseudocode)

   The following pseudocode demonstrates encoding and decoding byte
   arrays across all three Hinari variants.

```
   CONST BASE  = ["\u05D3", "\u05D5", "\u05D6", "\u05D9",
                  "\u05E8", "\u05F0", "\u05F1", "\u05F2"]
   CONST SUPP6 = ["\u05B0", "\u05B2", "\u05B3", "\u05B5",
                  "\u05B6", "\u05B7", "\u05BB", "\u05BD"]
   CONST SUPP9 = ["\u0594", "\u0595", "\u0598", "\u059D",
                  "\u059E", "\u059F", "\u05A0", "\u05A9"]

   FUNCTION EncodeHinari(bytes, variant):
       // variant MUST be 3, 6, or 9
       bitBuffer = 0
       bitCount = 0
       output = ""

       FOR EACH byte IN bytes:
           bitBuffer = (bitBuffer << 8) OR (byte AND 0xFF)
           bitCount = bitCount + 8

           WHILE bitCount >= variant:
               shift = bitCount - variant
               chunk = (bitBuffer >> shift) AND ((1 << variant) - 1)
               bitCount = bitCount - variant
               output = output + FormatGlyph(chunk, variant)

       // Handle remaining trailing bits with zero right-padding
       IF bitCount > 0:
           chunk = (bitBuffer << (variant - bitCount)) AND ((1 << variant) - 1)
           output = output + FormatGlyph(chunk, variant)

       RETURN output

   FUNCTION FormatGlyph(chunk, variant):
       IF variant == 3:
           RETURN BASE[chunk AND 0x07]
       ELSE IF variant == 6:
           oct1 = (chunk >> 3) AND 0x07
           oct2 = chunk AND 0x07
           RETURN BASE[oct1] + SUPP6[oct2]
       ELSE IF variant == 9:
           oct1 = (chunk >> 6) AND 0x07
           oct2 = (chunk >> 3) AND 0x07
           oct3 = chunk AND 0x07
           RETURN BASE[oct1] + SUPP6[oct2] + SUPP9[oct3]

   FUNCTION DecodeHinari(hinariString, variant):
       // variant MUST be 3, 6, or 9
       codePoints = ToUnicodeCodePoints(hinariString)
       step = variant / 3
       bitBuffer = 0
       bitCount = 0
       bytes = []

       FOR i = 0 TO Length(codePoints) - 1 STEP step:
           oct1 = IndexOf(BASE, codePoints[i])
           chunk = oct1
           IF variant >= 6:
               oct2 = IndexOf(SUPP6, codePoints[i + 1])
               chunk = (chunk << 3) OR oct2
           IF variant == 9:
               oct3 = IndexOf(SUPP9, codePoints[i + 2])
               chunk = (chunk << 3) OR oct3
           bitBuffer = (bitBuffer << variant) OR chunk
           bitCount = bitCount + variant
       WHILE bitCount >= 8:
       shift = bitCount - 8
       byte = (bitBuffer >> shift) AND 0xFF
       bitCount = bitCount - 8
       Append(bytes, byte)
       RETURN bytes
```

### 7. Security Considerations

### 8. Unicode Normalization

Hinari relies on exact code point sequences (BASE followed by SUPP6 followed by SUPP9).  
Because SUPP6 has Canonical Combining Class values 10..22 and SUPP9 has Canonical
Combining Class 230, standard NFC/NFD normalization preserves
relative ordering.  However, implementations MUST NOT apply
aggressive text sanitization that strips diacritical marks.

###  9. Right-to-Left (RTL) Rendering

Hebrew characters carry strong RTL bidirectional properties.  Display engines MAY visually
reorder glyph clusters right-to-left while logical memory order
remains big-endian left-to-right.

###  10. Padding Bits

Decoders MUST verify that non-zero padding bits are not used as a covert channel when strict canonical encoding
is required.

###  11. IANA Considerations

This memo includes no request to IANA.
