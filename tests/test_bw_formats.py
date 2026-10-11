"""Generated binary fixtures: no ROM bytes or Nintendo graphics in these tests."""
import struct
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from bw_formats import *
from import_bw_rom import species_map


def nitro(magic, tag, payload):
    size = 24 + len(payload)
    return struct.pack('<4sHHIHH4sI', magic, 0xFEFF, 0x100, size, 16, 1, tag, len(payload)+8) + payload


def anim(magic, kind, elements, durations, playback=2, loop=0):
    data = struct.pack('<HHIII', 1, len(elements), 24, 40, 40+8*len(elements)) + bytes(8)
    data += struct.pack('<HHHHII', len(elements), loop, kind, 1, playback, 0)
    offset = 0
    for element, duration in zip(elements,durations):
        data += struct.pack('<IHH', offset, duration, 0)
        offset += len(element)
    data += b''.join(elements)
    return nitro(magic, b'KNBA', data)


class FormatTests(unittest.TestCase):
    def test_compression_and_invalid_input(self):
        self.assertEqual(decompress(b'\x10\x06\0\0\x10abc\0\x02'),b'abcabc')
        self.assertEqual(decompress(b'\x11\x05\0\0\x20ab\x20\x01'),b'ababa')
        for invalid in (b'\x10\x03\0', b'\x10\x04\0\0\x80\0\0'):
            with self.assertRaises(FormatError):decompress(invalid)
        with self.assertRaises(FormatError):sections(b'garbage',b'NARC')

    def test_native_timing_and_affine(self):
        resource = anim(b'RNAN',1,[struct.pack('<Hhiihh',2,16384,8192,4096,3,-2),struct.pack('<Hhiihh',3,0,4096,4096,0,0)],[2,5],loop=1)
        timeline=animations(resource)[0]
        self.assertEqual(timeline.span(),(2,5))
        self.assertEqual(timeline.at(1).index,2)
        self.assertEqual(timeline.at(2).index,3)
        self.assertEqual(timeline.at(7).index,3)
        m=matrix(timeline.at(0))
        self.assertAlmostEqual(m[0],0,places=8)
        self.assertAlmostEqual(m[3],2,places=8)
        self.assertEqual(m[2],3)

    def test_multipart_composition_and_union(self):
        # One 8x8 tile; independently encoded all-red opaque indexed graphics.
        chars=nitro(b'RGCN',b'RAHC',struct.pack('<HHIIIII',1,1,3,0,0,32,24)+bytes([0x11])*32)
        cell=nitro(b'RECN',b'KBEC',struct.pack('<HHIIIII',1,0,24,0,0,0,0)+struct.pack('<HHI',1,0,0)+struct.pack('<HHH',0,0,0))
        parts=anim(b'RNAN',2,[struct.pack('<HHhh',0,0,0,0),struct.pack('<HHhh',0,0,4,0)],[2,3])
        layout=nitro(b'RCMN',b'KBCM',struct.pack('<HHIII',1,0,16,0,0)+struct.pack('<HHI',1,0,0)+struct.pack('<HhhH',0,0,0,32))
        outer=anim(b'RAMN',0,[struct.pack('<H',0)],[5])
        colors=[(0,0,0,0),(255,0,0,255)]+[(0,0,0,255)]*14
        image,durations,prefix,indices=render_animation([chars,cell,parts,layout,outer],colors)
        self.assertEqual(image.size,(192,96))
        self.assertEqual(durations,[2,3]);self.assertEqual(indices,[1,2]);self.assertEqual(prefix,0)
        first=image.crop((0,0,96,96)).getbbox();second=image.crop((96,0,192,96)).getbbox()
        self.assertEqual(second[0]-first[0],4)
        self.assertEqual(first[3],second[3])
        self.assertEqual(Tiles(chars).pixel(1023,0,0,8),0,'blank character padding')
        with self.assertRaises(FormatError):render_animation([chars[:-1],cell,parts,layout,outer],colors)

    def test_numbering_and_stems(self):
        names=species_map()
        self.assertEqual(len(names),649)
        self.assertEqual(names[571],'ZOROARK')
        self.assertEqual(names[29],'NIDORANfE')
        self.assertEqual(names[439],'MIMEJR')


if __name__=='__main__':unittest.main()
