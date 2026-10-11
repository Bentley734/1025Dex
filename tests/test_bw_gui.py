"""Check GUI destination safety and worker error/cancellation messages."""
import json
from pathlib import Path
import queue
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from bw_importer_gui import destination, run_import, FOLDER_NAME


class GuiTests(unittest.TestCase):
    def test_existing_import_is_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/FOLDER_NAME
            path.mkdir()
            marker = path/'keep.txt'
            marker.write_text('keep')
            with self.assertRaises(ValueError):
                destination(temp)
            self.assertEqual(marker.read_text(), 'keep')

    def test_mod_folder_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            (Path(temp)/'manifest.json').write_text(json.dumps({'id':'1025dex'}))
            with self.assertRaises(ValueError):
                destination(temp)

    def test_missing_rom_reports_error(self):
        with tempfile.TemporaryDirectory() as temp:
            events = queue.Queue()
            run_import(Path(temp)/'missing.nds', temp, events, threading.Event())
            self.assertEqual(events.get()[0], 'error')
            self.assertFalse((Path(temp)/FOLDER_NAME).exists())

    def test_cancel_does_not_install(self):
        with tempfile.TemporaryDirectory() as temp:
            rom = Path(temp)/'test.nds'
            rom.write_bytes(b'not a ROM')
            cancel = threading.Event()
            cancel.set()
            events = queue.Queue()
            run_import(rom, temp, events, cancel)
            self.assertEqual(events.get()[0], 'cancelled')
            self.assertEqual(list(Path(temp).iterdir()), [rom])

if __name__ == '__main__':
    unittest.main()
