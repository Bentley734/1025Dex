"""Double-click Windows interface for the independently written BW importer."""
import json
import os
from pathlib import Path
import queue
import sys
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import traceback
from import_bw_rom import build, ImportCancelled

VERSION = '1.0.0'
FOLDER_NAME = '1025dex-bw-sprites'


def mod_manifest(path):
    try:
        return json.loads((Path(path)/'manifest.json').read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return {}


def suggested_mods():
    """Check known save locations; never scan arbitrary personal directories."""
    appdata = Path(os.environ.get('APPDATA', Path.home()))
    candidates = [appdata/'pokemon-love2d/mods', appdata/'LOVE/pokemon-love2d/mods',
                  appdata/'Gen2Recomp/mods']
    for directory in candidates:
        if directory.is_dir() and any(mod_manifest(p).get('id') == '1025dex'
                                      for p in directory.iterdir() if p.is_dir()):
            return str(directory)
    return ''


def destination(folder):
    if not str(folder).strip():
        raise ValueError('Choose your Gen1Recomp mods folder first.')
    parent = Path(folder).expanduser().resolve()
    if not parent.is_dir():
        raise ValueError('The selected mods folder does not exist. Choose an existing folder.')
    if mod_manifest(parent).get('id'):
        raise ValueError('This is an individual mod folder. Choose the mods folder that contains it instead.')
    output = parent/FOLDER_NAME
    if output.exists():
        raise ValueError('A BW sprite companion already exists here. It has been left untouched. '
                         'Choose another destination folder if you want a separate import.')
    return output


def run_import(rom, folder, events, cancel, selected=None):
    """Worker never touches Tk; all messages return through the event queue."""
    try:
        output = destination(folder)
        if not Path(rom).is_file():
            raise ValueError('Choose an existing Black or White .nds ROM.')
        def progress(block, total, stem, imported, errors):
            events.put(('progress', block, total, stem, imported, errors))
        report = build(rom, output, selected=selected, progress=progress, cancel=cancel)
        events.put(('complete', str(output), report))
    except ImportCancelled:
        events.put(('cancelled',))
    except Exception as exc:
        events.put(('error', str(exc), traceback.format_exc()))


class Importer:
    def __init__(self, root):
        self.root = root
        self.root.title('1025Dex — Black / White Sprite Importer')
        self.root.geometry('760x600')
        self.root.minsize(680, 580)
        self.events, self.cancel = queue.Queue(), threading.Event()
        self.worker, self.output = None, None
        self.rom = tk.StringVar()
        self.folder = tk.StringVar(value=suggested_mods())
        self.status = tk.StringVar(value='Choose your ROM, then import its sprites.')
        style = ttk.Style(root)
        if 'vista' in style.theme_names():
            style.theme_use('vista')
        style.configure('Heading.TLabel', font=('Segoe UI', 19, 'bold'))
        style.configure('Body.TLabel', font=('Segoe UI', 10))
        frame = ttk.Frame(root, padding=24)
        frame.pack(fill='both', expand=True)
        frame.columnconfigure(0, weight=1)
        ttk.Label(frame, text='Black / White animated sprites', style='Heading.TLabel').grid(row=0, column=0, columnspan=2, sticky='w')
        ttk.Label(frame, text='Import battle sprites from your own ROM into 1025Dex.', style='Body.TLabel').grid(row=1, column=0, columnspan=2, sticky='w', pady=(8,20))
        ttk.Label(frame, text='1. Choose your Pokémon Black or White ROM').grid(row=2, column=0, columnspan=2, sticky='w')
        self.rom_entry = ttk.Entry(frame, textvariable=self.rom)
        self.rom_entry.grid(row=3, column=0, sticky='ew', pady=(6,18), padx=(0,10))
        self.rom_button = ttk.Button(frame, text='Choose ROM…', command=self.choose_rom)
        self.rom_button.grid(row=3, column=1, sticky='ew', pady=(6,18))
        ttk.Label(frame, text='2. Choose Gen1Recomp’s mods folder').grid(row=4, column=0, columnspan=2, sticky='w')
        self.folder_entry = ttk.Entry(frame, textvariable=self.folder)
        self.folder_entry.grid(row=5, column=0, sticky='ew', pady=(6,6), padx=(0,10))
        self.folder_button = ttk.Button(frame, text='Choose folder…', command=self.choose_folder)
        self.folder_button.grid(row=5, column=1, sticky='ew', pady=(6,6))
        self.hint = ttk.Label(frame, text='The folder containing your 1025Dex installation. A separate BW sprite mod will be added.', wraplength=680, style='Body.TLabel')
        self.hint.grid(row=6, column=0, columnspan=2, sticky='w', pady=(0,20))
        actions = ttk.Frame(frame)
        actions.grid(row=7, column=0, columnspan=2, sticky='w')
        self.start_button = ttk.Button(actions, text='Import sprites', command=self.start)
        self.start_button.pack(side='left', padx=(0,10))
        self.cancel_button = ttk.Button(actions, text='Cancel import', command=self.cancel_import, state='disabled')
        self.cancel_button.pack(side='left')
        self.bar = ttk.Progressbar(frame, mode='determinate', maximum=649)
        self.bar.grid(row=8, column=0, columnspan=2, sticky='ew', pady=(20,8))
        self.status_label = ttk.Label(frame, textvariable=self.status, wraplength=680, style='Body.TLabel')
        self.status_label.grid(row=9, column=0, columnspan=2, sticky='w')
        self.next_steps = ttk.Label(frame, text='When finished: restart Gen1Recomp, enable the BW sprite companion,\nthen set 1025Dex’s SPRITE STYLE to BW ROM.', wraplength=680, style='Body.TLabel')
        self.next_steps.grid(row=10, column=0, columnspan=2, sticky='w', pady=(18,12))
        bottom = ttk.Frame(frame)
        bottom.grid(row=11, column=0, columnspan=2, sticky='w')
        self.open_button = ttk.Button(bottom, text='Open imported mod folder', command=self.open_output, state='disabled')
        self.open_button.pack(side='left', padx=(0,12))
        ttk.Label(frame, text='Your ROM stays on this computer. Black/White 2 is not supported.', style='Body.TLabel').grid(row=12, column=0, columnspan=2, sticky='w', pady=(18,0))
        self.root.protocol('WM_DELETE_WINDOW', self.close)
        self.root.after(100, self.poll)

    def choose_rom(self):
        value = filedialog.askopenfilename(parent=self.root, title='Choose your Pokémon Black or White ROM', filetypes=[('Nintendo DS ROM', '*.nds'), ('All files', '*.*')])
        if value:
            self.rom.set(value)

    def choose_folder(self):
        value = filedialog.askdirectory(parent=self.root, title='Choose the mods folder containing 1025Dex', initialdir=self.folder.get() or str(Path.home()))
        if value:
            # Accept choosing the game/save directory as a convenience.
            directory = Path(value)
            if mod_manifest(directory).get('id') == '1025dex':
                directory = directory.parent
            elif (directory/'mods').is_dir():
                directory = directory/'mods'
            self.folder.set(str(directory))

    def set_busy(self, busy):
        for widget in (self.rom_entry, self.folder_entry, self.rom_button, self.folder_button, self.start_button):
            widget.configure(state='disabled' if busy else 'normal')
        self.cancel_button.configure(state='normal' if busy else 'disabled')

    def start(self, selected=None):
        if self.worker and self.worker.is_alive():
            return
        try:
            destination(self.folder.get())
            if not Path(self.rom.get()).is_file():
                raise ValueError('Choose your Black or White ROM first.')
        except ValueError as exc:
            messagebox.showerror('Choose import files', str(exc), parent=self.root)
            return
        self.output = None
        self.open_button.configure(state='disabled')
        self.bar['value'] = 0
        self.cancel.clear()
        self.set_busy(True)
        self.status.set('Reading your ROM…')
        self.worker = threading.Thread(target=run_import, args=(self.rom.get(), self.folder.get(), self.events, self.cancel, selected), daemon=False)
        self.worker.start()

    def cancel_import(self):
        self.cancel.set()
        self.cancel_button.configure(state='disabled')
        self.status.set('Cancelling after the current sprite. Your installed mods will stay untouched.')

    def poll(self):
        try:
            while True:
                event = self.events.get_nowait()
                kind = event[0]
                if kind == 'progress':
                    _, block, total, stem, imported, errors = event
                    self.bar['maximum'] = total
                    self.bar['value'] = min(block, total)
                    if not self.cancel.is_set():
                        self.status.set(f'{block} / {total} Pokémon — {stem.replace("_", " ")}\n{imported:,} sprites imported' + (f'; {errors} variants will use existing artwork' if errors else ''))
                elif kind == 'complete':
                    self.output = Path(event[1])
                    report = event[2]
                    self.bar['value'] = self.bar['maximum']
                    self.set_busy(False)
                    self.open_button.configure(state='normal')
                    self.status.set(f'Finished — {len(report["imported"]):,} sprite variants imported.' + (f' {len(report["errors"])} unavailable variants keep their existing artwork; see IMPORT-REPORT.json.' if report['errors'] else ''))
                    self.next_steps.configure(text='Ready! Restart Gen1Recomp and enable “1025Dex BW ROM Sprites (local)”.\nIn 1025Dex’s settings, choose SPRITE STYLE → BW ROM.')
                elif kind == 'cancelled':
                    self.set_busy(False)
                    self.status.set('Import cancelled. No companion was installed. You can try again.')
                elif kind == 'error':
                    self.set_busy(False)
                    self.status.set('Import could not finish. Your existing mods were left untouched.')
                    messagebox.showerror('Import failed', event[1], parent=self.root)
        except queue.Empty:
            pass
        self.root.after(100, self.poll)

    def open_output(self):
        if self.output and self.output.is_dir():
            os.startfile(str(self.output))

    def close(self):
        if self.worker and self.worker.is_alive():
            self.cancel_import()
            self.root.after(150, self.wait_close)
        else:
            self.root.destroy()

    def wait_close(self):
        if self.worker and self.worker.is_alive():
            self.root.after(150, self.wait_close)
        else:
            self.root.destroy()


def smoke_test(target, rom=None):
    """Own-app integration test; emits JSON without a console dependency."""
    root = tk.Tk()
    root.withdraw()
    app = Importer(root)
    root.update_idletasks()
    result = {'tk': tk.TkVersion, 'version': VERSION, 'species': len(__import__('import_bw_rom').species_map()),
              'title': root.title(), 'geometry': root.geometry(), 'buttons': [app.rom_button['text'],app.folder_button['text'],app.start_button['text']]}
    if rom:
        parent = Path(target).resolve().parent/'smoke-mods'
        parent.mkdir(exist_ok=True)
        app.rom.set(str(Path(rom).resolve()))
        app.folder.set(str(parent))
        app.start(selected={1,25,649})
        def wait():
            if app.worker and app.worker.is_alive():
                root.after(50, wait)
                return
            app.poll()
            result['output'] = str(app.output) if app.output else None
            result['status'] = app.status.get()
            result['restored_buttons'] = str(app.start_button['state'])
            Path(target).write_text(json.dumps(result,indent=2))
            root.destroy()
        root.after(50, wait)
        root.mainloop()
    else:
        Path(target).write_text(json.dumps(result,indent=2))
        root.destroy()


def main():
    if '--smoke-test' in sys.argv:
        index = sys.argv.index('--smoke-test')
        smoke_test(sys.argv[index+1], sys.argv[index+2] if len(sys.argv)>index+2 else None)
        return
    # Tk applies the system DPI scaling. Do not force fixed pixel scaling.
    root = tk.Tk()
    Importer(root)
    root.mainloop()


if __name__ == '__main__':
    main()
