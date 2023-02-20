fn main() {
    assert true
    assert !false

    assert 0 == 0
    assert 0 != 1
    assert 0 < 1
    assert 0 <= 1
    assert 1 > 0
    assert 1 >= 0

    assert true && true
    assert true || false

    assert 6 & 10 == 2
    assert 8 | 7 == 15
    assert 1 ^ 3 == 2
    assert 5 << 2 == 20
    assert 20 >> 1 == 10
}
