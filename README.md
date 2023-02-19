# valve

A WIP static analyzer for V that uses Z3. Aims to increase the correctness of V programs.

## Usage

```v
$ valve tests/basic.v
$ valve incorrect_program.v
incorrect_program.v:2:12: error: failed to prove assertion
    1 | fn main2() {
    2 |     assert false
      |            ~~~~~
    3 |     assert true
    4 |     assert 1 != 1
incorrect_program.v:4:12: error: failed to prove assertion
    2 |     assert false
    3 |     assert true
    4 |     assert 1 != 1
      |            ~~~~~~
    5 |     assert -1 < -2
    6 | }
incorrect_program.v:5:12: error: failed to prove assertion
    3 |     assert true
    4 |     assert 1 != 1
    5 |     assert -1 < -2
      |            ~~~~~~~
    6 | }
```

## TODO

- [ ] Check array access
- [ ] Variable support
- [ ] Check memory accesses?
- [ ] Ensure memory is freed?
