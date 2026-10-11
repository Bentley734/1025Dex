"""Independently written, bounds-checked Nintendo DS sprite format reader.

Format references (not implementation dependencies): see BW-ROM-IMPORT.md.
No cartridge data is included here. All offsets are checked before access.
"""
import math
import struct
from dataclasses import dataclass
from PIL import Image


class FormatError(ValueError):
    pass


class Reader:
    def __init__(self, data):
        self.data = memoryview(data)

    def span(self, offset, size):
        if offset < 0 or size < 0 or offset + size > len(self.data):
            raise FormatError(f"Truncated resource at {offset:#x} ({size} bytes)")
        return self.data[offset:offset + size]

    def unpack(self, fmt, offset):
        return struct.unpack(fmt, self.span(offset, struct.calcsize(fmt)))

    def u16(self, offset):
        return self.unpack('<H', offset)[0]

    def u32(self, offset):
        return self.unpack('<I', offset)[0]


def decompress(data):
    """Decode LZ10/LZ11; ordinary Nitro files pass through unchanged."""
    r = Reader(data)
    if not data or data[0] not in (0x10, 0x11):
        return bytes(data)
    kind = data[0]
    size = int.from_bytes(r.span(1, 3), 'little')
    pos = 4
    if not size and kind == 0x11:
        size, pos = r.u32(4), 8
    if not 0 < size <= 32 * 1024 * 1024:
        raise FormatError('Invalid decompressed size')
    out = bytearray()
    while len(out) < size:
        flags = r.span(pos, 1)[0]
        pos += 1
        for bit in range(7, -1, -1):
            if len(out) == size:
                break
            first = r.span(pos, 1)[0]
            pos += 1
            if not flags & (1 << bit):
                out.append(first)
                continue
            second = r.span(pos, 1)[0]
            pos += 1
            n = first >> 4
            if kind == 0x10:
                length, distance = n + 3, ((first & 15) << 8 | second) + 1
            elif n in (0, 1):
                third = r.span(pos, 1)[0]
                pos += 1
                if n == 0:
                    length = ((first & 15) << 4 | second >> 4) + 0x11
                    distance = ((second & 15) << 8 | third) + 1
                else:
                    fourth = r.span(pos, 1)[0]
                    pos += 1
                    length = ((first & 15) << 12 | second << 4 | third >> 4) + 0x111
                    distance = ((third & 15) << 8 | fourth) + 1
            else:
                length, distance = n + 1, ((first & 15) << 8 | second) + 1
            if distance > len(out) or len(out) + length > size:
                raise FormatError('Invalid LZ backreference')
            for _ in range(length):
                out.append(out[-distance])
    return bytes(out)


def sections(data, magic):
    data = decompress(data)
    r = Reader(data)
    if bytes(r.span(0, 4)) != magic or r.u16(4) not in (0xFEFF, 0xFFFE):
        raise FormatError(f'Expected {magic!r} Nitro resource')
    size, header, count = r.u32(8), r.u16(12), r.u16(14)
    if size > len(data) or header < 16 or count > 32:
        raise FormatError('Invalid Nitro header')
    result, pos = {}, header
    for _ in range(count):
        name = bytes(r.span(pos, 4))
        length = r.u32(pos + 4)
        if length < 8 or pos + length > size:
            raise FormatError('Invalid Nitro section')
        result[name] = Reader(r.span(pos, length))
        pos += length
    return result


def section(data, magic, name):
    bank = sections(data, magic)
    if name not in bank:
        raise FormatError(f'Missing {name!r} section')
    return bank[name]


def narc(data):
    banks = sections(data, b'NARC')
    fat, image = banks[b'BTAF'], banks[b'GMIF']
    count = fat.u16(8)
    if count > 32768:
        raise FormatError('Excessive archive members')
    result = []
    for index in range(count):
        start, end = fat.unpack('<II', 12 + index * 8)
        if end < start:
            raise FormatError('Reversed archive range')
        result.append(bytes(image.span(8 + start, end - start)))
    return result


def rom_archive(path):
    """Read only the requested NitroFS file, not the whole ROM into memory."""
    with open(path, 'rb') as rom:
        rom.seek(0, 2)
        size = rom.tell()
        def read(offset, length):
            if offset < 0 or length < 0 or offset + length > size:
                raise FormatError('ROM file range out of bounds')
            rom.seek(offset)
            value = rom.read(length)
            if len(value) != length:
                raise FormatError('Truncated ROM')
            return value
        header = Reader(read(0, 0x200))
        code = bytes(header.span(12, 4)).decode('ascii', errors='replace')
        if code[:3] not in ('IRB', 'IRA'):
            raise FormatError(f'{code}: supply Pokemon Black or White, not BW2 or another game')
        fnt_offset, fnt_size, fat_offset, fat_size = header.unpack('<IIII', 0x40)
        if fnt_size > 8 * 1024 * 1024 or fat_size > 8 * 1024 * 1024:
            raise FormatError('Invalid ROM filesystem size')
        fnt, fat = Reader(read(fnt_offset, fnt_size)), Reader(read(fat_offset, fat_size))
        directory = 0xF000
        for component in ('a', '0', '0', '4'):
            table = (directory - 0xF000) * 8
            cursor, file_id = fnt.u32(table), fnt.u16(table + 4)
            found = None
            for _ in range(65536):
                flag = fnt.span(cursor, 1)[0]
                cursor += 1
                if flag == 0:
                    break
                length = flag & 127
                name = bytes(fnt.span(cursor, length)).decode('ascii')
                cursor += length
                is_dir = bool(flag & 128)
                target = fnt.u16(cursor) if is_dir else file_id
                if is_dir:
                    cursor += 2
                else:
                    file_id += 1
                if name == component:
                    found = (is_dir, target)
                    break
            if found is None:
                raise FormatError('ROM has no /a/0/0/4 sprite archive')
            if component != '4':
                if not found[0]:
                    raise FormatError('Invalid filesystem directory')
                directory = found[1]
        if found[0]:
            raise FormatError('Sprite archive is a directory')
        start, end = fat.unpack('<II', found[1] * 8)
        if end - start > 64 * 1024 * 1024 or end < start:
            raise FormatError('Invalid sprite archive size')
        return code, narc(read(start, end - start))


def palette(data):
    r = section(data, b'RLCN', b'TTLP')
    values = r.span(8 + r.u32(20), r.u32(16))
    colors = []
    for (value,) in struct.iter_unpack('<H', values):
        colors.append(tuple(((value >> shift) & 31) * 255 // 31 for shift in (0, 5, 10)) + (255,))
    if not 16 <= len(colors) <= 256:
        raise FormatError('Invalid palette length')
    return colors


class Tiles:
    def __init__(self, data):
        r = section(data, b'RGCN', b'RAHC')
        self.bpp = {3: 4, 4: 8}.get(r.u32(12))
        if self.bpp is None:
            raise FormatError('Unsupported character depth')
        self.raw = bytes(r.span(32, r.u32(24)))
        self.linear = r.u32(20) == 1
        self.mapping = r.u32(16)
        # BW bitmap character data uses the DS 256px bitmap stride.
        self.stride = 32 if self.linear else 0

    def pixel(self, tile, x, y, width):
        stride = self.stride or width // 8
        tile += y // 8 * stride + x // 8
        index = ((tile // 32 * 8 + y % 8) * 256 + tile % 32 * 8 + x % 8
                 if self.linear else tile * 64 + y % 8 * 8 + x % 8)
        byte_index = index // 2 if self.bpp == 4 else index
        if byte_index >= len(self.raw):
            # Some legal OBJ rectangles include blank padding beyond the
            # uploaded characters (Hydreigon's lower front cells, for example).
            # The missing character area contains transparent index zero.
            return 0
        byte = self.raw[byte_index]
        return (byte >> (4 * (index % 2))) & 15 if self.bpp == 4 else byte


def cells(data):
    r = section(data, b'RECN', b'KBEC')
    count, extended = r.u16(8), r.u16(10) & 1
    entry_size = 16 if extended else 8
    table = 8 + r.u32(12)
    oam_base = table + count * entry_size
    if not 0 < count <= 1024:
        raise FormatError('Invalid cell count')
    result = []
    sizes = (((8, 8), (16, 16), (32, 32), (64, 64)),
             ((16, 8), (32, 8), (32, 16), (64, 32)),
             ((8, 16), (8, 32), (16, 32), (32, 64)))
    for index in range(count):
        entry = table + index * entry_size
        objects = []
        number = r.u16(entry)
        if number > 128:
            raise FormatError('Too many OAM objects')
        for i in range(number):
            a, b, c = r.unpack('<HHH', oam_base + r.u32(entry + 4) + i * 6)
            shape = a >> 14
            if shape == 3:
                raise FormatError('Invalid OAM shape')
            if not a & 256 and a & 512:
                continue  # disabled OBJ
            w, h = sizes[shape][b >> 14]
            x, y = b & 511, a & 255
            x = x - 512 if x >= 256 else x
            y = y - 256 if y >= 128 else y
            affine = bool(a & 256)
            if affine and a & 512:
                x, y = x + w // 2, y + h // 2
            objects.append((x, y, w, h, c & 1023, c >> 12, (c >> 10) & 3,
                            not affine and bool(b & 4096), not affine and bool(b & 8192)))
        result.append(objects)
    return result


@dataclass(frozen=True)
class Pose:
    index: int
    duration: int
    rotation: int = 0
    sx: float = 1
    sy: float = 1
    x: int = 0
    y: int = 0


@dataclass
class Timeline:
    frames: list
    loop_start: int
    playback: int

    def schedule(self):
        forward = list(range(len(self.frames)))
        if self.playback in (3, 4):
            forward += list(range(len(self.frames) - 2, (self.loop_start if self.playback == 4 else 0) - 1, -1))
        return forward

    def span(self):
        order = self.schedule()
        prefix = sum(self.frames[i].duration for i in order[:self.loop_start]) if self.playback in (2, 4) else sum(self.frames[i].duration for i in order)
        total = sum(self.frames[i].duration for i in order)
        return prefix, max(1, total - prefix) if self.playback in (2, 4) else 1

    def locate(self, tick):
        order = self.schedule()
        prefix, period = self.span()
        if tick >= prefix:
            tick = prefix + (tick - prefix) % period if self.playback in (2, 4) else max(0, prefix - 1)
        for index in order:
            pose = self.frames[index]
            if tick < pose.duration:
                return pose, tick
            tick -= pose.duration
        return self.frames[order[-1]], max(0, self.frames[order[-1]].duration - 1)

    def at(self, tick):
        return self.locate(tick)[0]


def animations(data, magic=b'RNAN'):
    r = section(data, magic, b'KNBA')
    table, headers, elements = (8 + r.u32(o) for o in (12, 16, 20))
    result = []
    count = r.u16(8)
    if not 0 < count <= 2048:
        raise FormatError('Invalid animation count')
    for index in range(count):
        p = table + index * 16
        n, loop, kind, _, playback, offset = r.unpack('<HHHHII', p)
        if not 0 < n <= 4096 or kind not in (0, 1, 2, 3) or playback not in (1, 2, 3, 4) or loop >= n:
            raise FormatError('Unsupported animation header')
        frames = []
        for i in range(n):
            element, duration, _ = r.unpack('<IHH', headers + offset + i * 8)
            p = elements + element
            cell = r.u16(p)
            if kind == 1:
                cell, rotation, sx, sy, x, y = r.unpack('<Hhiihh', p)
                if sx == 0 or sy == 0:
                    raise FormatError('Singular animation transform')
                frames.append(Pose(cell, duration, rotation, sx / 4096, sy / 4096, x, y))
            elif kind == 2:
                cell, _, x, y = r.unpack('<HHhh', p)
                frames.append(Pose(cell, duration, x=x, y=y))
            else:
                frames.append(Pose(cell, duration))
        result.append(Timeline(frames, loop, playback))
    return result


def maps(data):
    r = section(data, b'RCMN', b'KBCM')
    count, table = r.u16(8), 8 + r.u32(12)
    if not 0 < count <= 2048:
        raise FormatError('Invalid multicell count')
    records = table + count * 8
    result = []
    for i in range(count):
        p = table + i * 8
        n = r.u16(p)
        if n > 128:
            raise FormatError('Too many multicell parts')
        result.append([r.unpack('<HhhH', records + r.u32(p + 4) + j * 8) for j in range(n)])
    return result


def matrix(pose, x=0, y=0):
    angle = pose.rotation * math.tau / 65536
    c, s = math.cos(angle), math.sin(angle)
    return (c * pose.sx, -s * pose.sy, pose.x + x,
            s * pose.sx, c * pose.sy, pose.y + y)


def compose(a, b):
    return (a[0]*b[0]+a[1]*b[3], a[0]*b[1]+a[1]*b[4], a[0]*b[2]+a[1]*b[5]+a[2],
            a[3]*b[0]+a[4]*b[3], a[3]*b[1]+a[4]*b[4], a[3]*b[2]+a[4]*b[5]+a[5])


def render_animation(resources, colors, animation=0, max_ticks=36000):
    """Reconstruct multipart animation at every DS tick, then losslessly coalesce.

    A single union canvas is shared by ALL frames. Never trim frames separately.
    Returns square horizontal strip, durations, and loop start tick.
    """
    tiles = Tiles(resources[0])
    cell_bank, parts, layouts = cells(resources[1]), animations(resources[2]), maps(resources[3])
    outer_bank = animations(resources[4], b'RAMN')
    if not 0 <= animation < len(outer_bank):
        raise FormatError('Requested NMAR animation does not exist')
    outer = outer_bank[animation]
    active = set()
    for pose in outer.frames:
        if pose.index >= len(layouts):
            raise FormatError('Invalid NMAR map index')
        active.update(record[0] for record in layouts[pose.index])
    if any(i >= len(parts) for i in active):
        raise FormatError('Invalid NANR animation index')
    # NMAR controls the complete battle sequence, including idle/break changes.
    # The component animation clock begins at the selected multicell frame.
    prefix, period = outer.span()
    if prefix + period > max_ticks:
        raise FormatError(f'Animation period {prefix + period} exceeds {max_ticks} ticks; no truncation performed')
    plans, bounds = [], [0, 0, 0, 0]
    for tick in range(prefix + period):
        whole, part_tick = outer.locate(tick)
        plan = []
        for animation_id, x, y, flags in layouts[whole.index]:
            pose = parts[animation_id].at(part_tick)
            if pose.index >= len(cell_bank):
                raise FormatError('Invalid NCER cell index')
            transform = compose(matrix(whole), matrix(pose, x, y))
            for obj in cell_bank[pose.index]:
                ox, oy, w, h = obj[:4]
                m = compose(transform, (1, 0, ox, 0, 1, oy))
                corners = [(m[0]*px+m[1]*py+m[2], m[3]*px+m[4]*py+m[5]) for px, py in ((0,0),(w,0),(0,h),(w,h))]
                for px, py in corners:
                    bounds = [min(bounds[0], math.floor(px)), min(bounds[1], math.floor(py)), max(bounds[2], math.ceil(px)), max(bounds[3], math.ceil(py))]
                plan.append((obj, m, len(plan)))
        plans.append(sorted(plan, key=lambda item: (item[0][6], item[2]), reverse=True))
    left, top, right, bottom = bounds
    side = max(96, right-left, bottom-top)
    if side > 512:
        raise FormatError('Animation exceeds 512px canvas')
    left -= (side - (right-left)) // 2
    top -= side - (bottom-top)
    frames, durations, frame_indices, cache = [], [], [], {}
    for tick, plan in enumerate(plans):
        key = tuple(plan)
        if key in cache:
            index = cache[key]
            if frame_indices and frame_indices[-1] == index and tick != prefix:
                durations[-1] += 1
            else:
                frame_indices.append(index)
                durations.append(1)
            continue
        canvas = Image.new('RGBA', (side, side))
        for obj, m, _ in plan:
            _, _, w, h, tile, bank, _, flip_x, flip_y = obj
            source = Image.new('RGBA', (w, h))
            pixels = source.load()
            for y in range(h):
                for x in range(w):
                    value = tiles.pixel(tile, w-1-x if flip_x else x, h-1-y if flip_y else y, w)
                    if value:
                        index = value + (bank * 16 if tiles.bpp == 4 and len(colors) > 16 else 0)
                        if index >= len(colors):
                            raise FormatError('Palette index out of bounds')
                        pixels[x, y] = colors[index]
            determinant = m[0]*m[4]-m[1]*m[3]
            if abs(determinant) < 1e-9:
                raise FormatError('Singular composed transform')
            a,b,d,e = m[4]/determinant, -m[1]/determinant, -m[3]/determinant, m[0]/determinant
            dx,dy = left-m[2], top-m[5]
            affine = (a,b,a*dx+b*dy,d,e,d*dx+e*dy)
            canvas.alpha_composite(source.transform((side,side), Image.Transform.AFFINE, affine, Image.Resampling.NEAREST))
        # Preserve the loop boundary even when identical images meet there.
        pixels = canvas.tobytes()
        index = next((i + 1 for i, frame in enumerate(frames) if frame.tobytes() == pixels), None)
        if index is None:
            frames.append(canvas)
            index = len(frames)
        cache[key] = index
        if frame_indices and frame_indices[-1] == index and tick != prefix:
            durations[-1] += 1
        else:
            frame_indices.append(index)
            durations.append(1)
    if not any(frame.getbbox() for frame in frames):
        raise FormatError('Animation contains no visible pixels')
    # Strips are decoded into CPU ImageData, never uploaded as one GPU texture.
    # Only the final small frame canvases become textures in the renderer.
    if side * side * len(frames) > 64 * 1024 * 1024:
        raise FormatError('Animation exceeds 256 MiB decoded-image budget')
    strip = Image.new('RGBA', (side * len(frames), side))
    for i, frame in enumerate(frames):
        strip.paste(frame, (i*side, 0))
    return strip, durations, prefix, frame_indices
