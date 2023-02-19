.PHONY: FORCE

tests/%.v: valve FORCE
	./valve $@

check: valve FORCE $(wildcard tests/*.v)
	@:

valve: $(wildcard *.v)
	v -prod -o valve .

FORCE:
