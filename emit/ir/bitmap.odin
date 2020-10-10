package ir

Bitmap :: struct
{
    bits: u64,
    chunks: []u64,
}

make_bitmap :: proc(size: u64) -> Bitmap
{
    bmp: Bitmap;
    bmp.bits = size;
    bmp.chunks = make([]u64, size / size_of(bmp.chunks[0]));
    return bmp;
}

bitmap_set :: proc(using bmp: ^Bitmap, bit: u64)
{
    assert(bit < bits);
    chunk_idx := bit / size_of(chunks[0]);
    bit_idx   := bit % size_of(chunks[0]);
    chunks[chunk_idx] |= bit << bit_idx;
}

bitmap_unset :: proc(using bmp: ^Bitmap, bit: u64)
{
    assert(bit < bits);
    chunk_idx := bit / size_of(chunks[0]);
    bit_idx   := bit % size_of(chunks[0]);
    chunks[chunk_idx] &= ~(bit << bit_idx);
}

bitmap_get :: proc(using bmp: ^Bitmap, bit: u64) -> bool
{
    assert(bit < bits);
    chunk_idx := bit / size_of(chunks[0]);
    bit_idx   := bit % size_of(chunks[0]);
    return bool((chunks[chunk_idx] >> bit_idx) & 0b1);
}