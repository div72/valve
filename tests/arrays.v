fn main() {
    arr := [1, 2, 3, 4]
    fixed_array := [1, 2, 3, 4, 5]!

    println(arr[0])
    println(fixed_array[4])

    assert arr[0] == 1
    assert fixed_array[fixed_array.len - 1] == 5

    if arr.len > 5 {
        println(arr[4])
    }
}
