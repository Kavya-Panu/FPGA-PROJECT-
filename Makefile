.PHONY: test demo lint synth
test:
	python3 tools/check.py
demo:
	python3 tests/run.py --demo --waves
lint:
	python3 tools/lint.py
synth:
	python3 -c "from pathlib import Path; Path('build').mkdir(exist_ok=True)"
	yosys -l build/synthesis.log scripts/synth.ys
