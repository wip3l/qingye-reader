"""Run after building/installing entry@ohosTest. Only edits entry_test preferences."""
import argparse
import json
import pathlib
import re
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--hdc', required=True)
parser.add_argument('--device', required=True)
parser.add_argument('--precise', action='store_true', help='Verify tap-to-edit numeric input')
args = parser.parse_args()
prefix = [args.hdc, '-t', args.device]


def hdc(*command):
    return subprocess.run(prefix + list(command), check=True, capture_output=True, timeout=20)


def flatten(node):
    yield node.get('attributes', {})
    for child in node.get('children', []):
        yield from flatten(child)


with tempfile.TemporaryDirectory(prefix='reader-stepper-') as directory:
    tree_path = pathlib.Path(directory) / 'layout.json'
    log_path = pathlib.Path(directory) / 'runner.log'
    with log_path.open('wb') as log:
        runner = subprocess.Popen(prefix + ['shell', 'aa', 'test', '-b', 'io.legado.read', '-m', 'entry_test',
            '-s', 'unittest', '/ets/testrunner/ReaderFontWeightUiTestRunner', '-s', 'timeout', '120000'], stdout=log, stderr=log)

        def snapshot():
            hdc('shell', 'uitest', 'dumpLayout', '-b', 'io.legado.read', '-p', '/data/local/tmp/reader-stepper-ui.json')
            hdc('file', 'recv', '/data/local/tmp/reader-stepper-ui.json', str(tree_path))
            return list(flatten(json.loads(tree_path.read_text(encoding='utf-8'))))

        def find(key, value):
            all_nodes = snapshot()
            nodes = [node for node in all_nodes if node.get(key) == value]
            # Some releases omit accessibilityText from dumpLayout. Locate the actual
            # Button immediately beside the identified value label, using observed bounds.
            if not nodes and key == 'description':
                match = re.fullmatch(r'(增大|减小)(正文|标题|规则)字体粗细', value)
                if match:
                    labels = [node for node in all_nodes if node.get('id') == f'reader_font_weight_{match[2]}']
                    assert len(labels) == 1
                    bounds = [int(x) for x in re.findall(r'-?\d+', labels[0]['bounds'])]
                    center_y = (bounds[1] + bounds[3]) / 2
                    for node in all_nodes:
                        if node.get('type') != 'Button':
                            continue
                        box = [int(x) for x in re.findall(r'-?\d+', node['bounds'])]
                        if abs((box[1] + box[3]) / 2 - center_y) > 5:
                            continue
                        if (match[1] == '增大' and box[0] >= bounds[2]) or (match[1] == '减小' and box[2] <= bounds[0]):
                            nodes.append(node)
            assert len(nodes) == 1, f'Expected one {key}={value}, got {len(nodes)}'
            return nodes[0]

        def click(key, value):
            node = find(key, value)
            assert str(node.get('enabled')).lower() == 'true', f'{value} disabled'
            bounds = [int(x) for x in re.findall(r'-?\d+', node['bounds'])]
            assert len(bounds) == 4
            hdc('shell', 'uitest', 'uiInput', 'click', str((bounds[0] + bounds[2]) // 2), str((bounds[1] + bounds[3]) // 2))

        def expect(scope, value):
            node = find('id', f'reader_font_weight_{scope}')
            assert node['text'] == str(value), f'{scope}: expected {value}, got {node["text"]}'

        def enter_weight(scope, value, expected):
            click('id', f'reader_font_weight_{scope}')
            node = find('id', f'reader_font_weight_input_{scope}')
            assert node['focused'] == 'true', f'{scope}: numeric editor did not receive focus'
            box = [int(x) for x in re.findall(r'-?\d+', node['bounds'])]
            if value:
                hdc('shell', 'uitest', 'uiInput', 'inputText', str((box[0] + box[2]) // 2),
                    str((box[1] + box[3]) // 2), value)
            # An actual keyboard Enter exercises onSubmit (and subsequent onBlur).
            hdc('shell', 'uitest', 'uiInput', 'keyEvent', '2054')
            expect(scope, expected)

        try:
            deadline = time.monotonic() + 15
            while True:
                try:
                    expect('正文', 400)
                    break
                except (AssertionError, subprocess.SubprocessError):
                    if time.monotonic() >= deadline:
                        raise
                    time.sleep(.3)
            if args.precise:
                enter_weight('正文', '425', 425)
                click('description', '增大正文字体粗细')
                expect('正文', 475)
                click('description', '减小正文字体粗细')
                expect('正文', 425)
                enter_weight('标题', '675', 675)
                enter_weight('规则', '537', 537)
                enter_weight('正文', '', 425)
                print('PASS: exact integers for all three controls, empty input and stepping from the entered value', flush=True)
                enter_weight('正文', '1', 50)
                assert find('description', '减小正文字体粗细')['enabled'] == 'false'
                enter_weight('正文', '999', 900)
                assert find('description', '增大正文字体粗细')['enabled'] == 'false'
                enter_weight('正文', '425', 425)
                click('id', 'clear_weight_display')
                expect('正文', 400)
                click('id', 'reload_weight')
                assert find('id', 'weight_parent_state')['text'] == '425/675/537'
                for scope, value in [('正文', 425), ('标题', 675), ('规则', 537)]:
                    expect(scope, value)
                print('PASS: input clamps to 50–900 and all precise values persist after reload', flush=True)
            else:
                for scope in ['正文', '标题', '规则']:
                    initial = 600 if scope == '标题' else 400
                    for step in range(1, 4):
                        click('description', f'增大{scope}字体粗细')
                        expect(scope, initial + step * 50)
                    click('description', f'减小{scope}字体粗细')
                    expect(scope, initial + 100)
                    print(f'PASS: {scope} repeated clicks and reversal', flush=True)
                assert find('id', 'weight_parent_state')['text'] == '500/700/500'
                click('id', 'set_weight_min')
                expect('正文', 50)
                assert find('description', '减小正文字体粗细')['enabled'] == 'false'
                click('description', '增大正文字体粗细')
                expect('正文', 100)
                assert find('description', '减小正文字体粗细')['enabled'] == 'true'
                click('id', 'set_weight_max')
                expect('正文', 900)
                assert find('description', '增大正文字体粗细')['enabled'] == 'false'
                click('description', '减小正文字体粗细')
                expect('正文', 850)
                assert find('description', '增大正文字体粗细')['enabled'] == 'true'
                print('PASS: external prop updates, both limits and button re-enabling', flush=True)
                click('id', 'clear_weight_display')
                expect('正文', 400)
                click('id', 'reload_weight')
                assert find('id', 'weight_reload_status')['text'] == '已恢复'
                assert find('id', 'weight_parent_state')['text'] == '850/700/500'
                for scope, value in [('正文', 850), ('标题', 700), ('规则', 500)]:
                    expect(scope, value)
                print('PASS: parent state and preferences reload retain all three independent values', flush=True)
        finally:
            try:
                click('id', 'finish_weight_test')
            except (AssertionError, subprocess.SubprocessError):
                pass
            try:
                runner.wait(timeout=8)
            except subprocess.TimeoutExpired:
                runner.terminate()
