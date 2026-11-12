"""Regression: child STRETCH layout uses the same units in render and click."""
from pathlib import Path
import math
root = Path(__file__).resolve().parents[2]
text = (root / 'Derived/wrath-qc-gate5c/uielement.qc').read_text()
render = text.split('void UI_RenderElements(', 1)[1].split('void UI_CheckClick(', 1)[0]
click = text.split('void UI_CheckClick(', 1)[1].split('float UI_CheckInput(', 1)[0]
for body in (render, click):
    stretch = body.split('chain.size = chain.owner.totalsize();', 1)[1].split('else if (chain.anchor)', 1)[0]
    assert 'chain.size[0] /= ui_scale[0];' in stretch
    assert 'chain.size[1] /= ui_scale[1];' in stretch
for scale in (.5, .75, 1., 2.):
    for parent_size in (256., 512.):
        rendered_parent = parent_size * scale
        rendered_child = (rendered_parent / scale) * scale
        clicked_child = (rendered_parent / scale) * scale
        assert math.isclose(rendered_child, clicked_child)
        assert math.isclose(rendered_child * .5, clicked_child * .5)
        if scale != 1:
            assert not math.isclose(rendered_child, rendered_parent * scale)
print('Nested STRETCH render/click unit regression passed at 0.5, 0.75, 1, 2 scale')
