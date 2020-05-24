#!/usr/bin/env python3


import gzip
import itertools
import json
import os
import re
import subprocess


def source_lists():
    """Return a list of the filenames of all APT source lists."""
    files = ['/etc/apt/sources.list']
    folder = '/etc/apt/sources.list.d'
    for file in os.listdir(folder):
        if file.endswith('.list'):
            files.append(os.path.join(folder, file))
    return files


def file_ppas(filename):
    """Return a list of all PPA's from an APT source list file."""
    regex = r'^deb http://ppa.launchpad.net/([a-z0-9\-]+/[a-z0-9\-]+)'
    ppas = []
    with open(filename, 'r') as file:
        for line in file:
            match = re.search(regex, line)
            if match:
                ppas.append(f'ppa:{match.group(1)}')
    return ppas


def ppas():
    """Return the set of PPA's on the system."""
    return set([ppa for file in source_lists() for ppa in file_ppas(file)])


def add_apt_repository(repository):
    """Add an APT repository to the system.

    To save time, this doesn't update the package cache afterward."""
    subprocess.run(['sudo', 'add-apt-repository', '--no-update', repository])


def remove_apt_repository(repository):
    """Remove an APT repository to the system."""
    subprocess.run(['sudo', 'add-apt-repository', '--remove', repository])


def apt_update():
    """Update the APT package index."""
    subprocess.run(['sudo', 'apt-get', 'update'])


def manual_packages():
    """Return a list of manual APT packages according to apt-mark."""
    command = ['apt-mark', 'showmanual']
    output = subprocess.check_output(command, encoding='utf-8')
    return output.splitlines()


def fresh_install_packages():
    """Return a list of APT packages present at system setup."""
    packages = []
    with gzip.open('/var/log/installer/initial-status.gz', 'rt') as file:
        for line in file.read().splitlines():
            match = re.search(r'^Package: (.*)', line)
            if match:
                packages.append(match.group(1))
    return packages


def apt_packages():
    """Return the set of manually-installed APT packages."""
    return set(manual_packages()) - set(fresh_install_packages())


def apt_install(package):
    """Install an APT package to the system."""
    subprocess.run(['sudo', 'apt-get', 'install', package])


def apt_unmark(package):
    """Unmark an APT package as being manually installed."""
    subprocess.run(['sudo', 'apt-mark', 'auto', package])


def in_repository(package):
    """Return truthy iff package is in an installed APT repository."""
    command = ['apt-cache', 'policy', package]
    output = subprocess.check_output(command, encoding='utf-8')
    lines = output.splitlines()
    # first line of entry for the installed version
    i = next(i for i, line in enumerate(lines) if line.startswith(' *** '))
    # the only line in that entry is just saying it's installed
    no_repository = lines[i + 1].startswith('        100 /var/lib/dpkg/status')
    return not no_repository


def snaps():
    """Return a dictionary of installed snaps.

    The dictionary maps each snap name to a dictionary specifying
    (possibly) its 'channel' and 'confinement'. The 'channel' is missing
    if it would be latest/stable, and the 'confinement' is missing if it
    would be strict."""
    # seems to automatically add --color=never and --unicode=never,
    # although apparently the output can include ellipsis characters …
    # even if --unicode=never is specified
    command = ['snap', 'list']
    output = subprocess.check_output(command, encoding='utf-8')
    table = [re.split(r'  +', line) for line in output.splitlines()]
    header = table[0]
    name_index = header.index('Name')
    channel_index = header.index('Tracking')
    confinement_index = header.index('Notes')
    rows = table[1:]
    dict = {}
    for row in rows:
        name = row[name_index]
        chan = row[channel_index]
        conf = row[confinement_index]
        entry = {}
        if not chan.startswith('latest/stable'):
            entry['channel'] = chan
        if conf != '-':
            entry['confinement'] = conf
        dict[name] = entry
    return dict


class Snap:
    """A snap with a name, and possibly a channel and confinement."""

    def args(self):
        """Return a list of arguments to pass this snap to commands."""
        l = [self.name]
        if hasattr(self, 'channel'):
            l.append(f'--channel={self.channel}')
        if hasattr(self, 'confinement'):
            l.append(f'--{self.confinement}')
        return l

    def __str__(self):
        return ' '.join(self.args())


def remove_keys(dict, keys):
    """Returns a new dictionary by removing keys from dict.

    Does not modify dict."""
    # for fast lookup, just in case keys isn't already a set
    key_set = set(keys)
    return {key: dict[key] for key in dict if key not in key_set}


def select_mismatched(d1, d2):
    """Returns a copy of d1 with only the entries that disagree with d2.

    Both are dictionaries. Does not modify d1 or d2."""
    return {k: d1[k] for k in d1 if k in d2 and d2[k] != d1[k]}


def entry_to_snap(key, value):
    """Returns a snap object corresponding to the key-value pair.

    The pair takes the same form as entries in the dictionary returned
    by snaps()."""
    snap = Snap()
    snap.name = key
    if 'channel' in value:
        snap.channel = value['channel']
    if 'confinement' in value:
        snap.confinement = value['confinement']
    return snap


def snap_dict_to_list(dict):
    """Return a list of snaps, if dict maps snaps to properties.

    The input dict takes the same format as the one returned by
    snaps()."""
    return [entry_to_snap(name, dict[name]) for name in dict]


def snap_install(snap):
    """Install a snap."""
    subprocess.run(['sudo', 'snap', 'install'] + snap.args())


def snap_switch(snap):
    """Switch the channel and confinement of a snap."""
    subprocess.run(['sudo', 'snap', 'switch'] + snap.args())


def snap_remove(snap):
    """Remove a snap."""
    subprocess.run(['sudo', 'snap', 'remove'] + snap.args())


def slurp(path):
    """Return contents of file at path."""
    with open(path) as f:
        return f.read()


def spit(path, content):
    """Write content to file at path."""
    with open(path, 'w') as f:
        f.write(content)


def process_list(things, preface, instructions, query, action, failure):
    """Interactively process a list of things.

    The preface (followed by a colon) is printed prior to the list of
    things, where each thing is indended with two spaces. Then each of
    the instructions is printed on its own line, followed by a blank
    line. Next, for each thing, the query is printed, followed by a
    question mark and the options y/n. If the user selects y, the action
    is performed on the thing. If an exception is thrown while
    performing the action, the failure string is printed, followed by a
    colon and the thing for which the action was being performed."""
    if things:
        print(f'{preface}:')
        for thing in things:
            print(f'  {thing}')
        print('\n'.join(instructions))
        print()
        for thing in things:
            print(f'  {thing}')
            choice = None
            while not choice:
                choice = input(f'{query}? (y/n) ')
                if choice not in {'y', 'n'}:
                    choice = None
            if choice == 'y':
                try:
                    action(thing)
                # usually means user hit Ctrl-C
                except:
                    print(f'{failure}: {thing}')
            print()


ppas_file = 'ppas.json'
ppas_saved = set(json.loads(slurp(ppas_file)))
ppas_here = ppas()
process_list(
    ppas_saved - ppas_here,
    f'Repositories in {ppas_file} but not on this system',
    ['Choose which repositories to add to the system',
     f'and which ones to remove from the {ppas_file} file.'],
    'Add this PPA',
    add_apt_repository,
    'Failed to add APT repository')
process_list(
    ppas_here - ppas_saved,
    f'PPA repositories on this system but not in the {ppas_file} file',
    ['Choose which repositories to remove from the system',
     f'and which ones to add to the {ppas_file} file.'],
    'Remove this PPA',
    remove_apt_repository,
    'Failed to remove APT repository')
ppas_after = ppas()
spit(ppas_file, json.dumps(sorted(ppas_after), indent=2) + '\n')

# run apt-get update if we've added any repositories
if ppas_after - ppas_here:
    print('Updating APT package index...')
    apt_update()
    print('Done.')
    print()

apt_file = 'apt_packages.json'
apt_saved = set(json.loads(slurp(apt_file)))
apt_here = apt_packages()
process_list(
    apt_saved - apt_here,
    f'APT packages in {apt_file} but not manually installed on this system',
    ['Choose which packages to manually install in the system',
     f'and which ones to remove from the {apt_file} file.'],
    'Install this package',
    apt_install,
    'Failed to install APT package')
process_list(
    apt_here - apt_saved,
    f'APT packages manually installed on this system but not in {apt_file}',
    ['Choose which packages to unmark as manual in the system',
     f'and which ones to add to the {apt_file} file.'],
    'Unmark this package',
    apt_unmark,
    'Failed to unmark APT package')
spit(apt_file, json.dumps(sorted(apt_packages()), indent=2) + '\n')

snaps_file = 'snaps.json'
snaps_saved = json.loads(slurp(snaps_file))
snaps_here = snaps()
process_list(
    snap_dict_to_list(remove_keys(snaps_saved, snaps_here.keys())),
    f'Snaps in {snaps_file} but not installed on this system',
    ['Choose which snaps to install in the system',
     f'and which ones to remove from the {snaps_file} file.'],
    'Install this snap',
    snap_install,
    'Failed to install snap')
process_list(
    snap_dict_to_list(select_mismatched(snaps_here, snaps_saved)),
    f'Snaps installed on this system differing from {snaps_file}',
    ['Choose which snaps to switch in the system',
     f'and which ones to change in the {snaps_file} file.'],
    'Switch this snap',
    snap_switch,
    'Failed to switch snap')
process_list(
    snap_dict_to_list(remove_keys(snaps_here, snaps_saved.keys())),
    f'Snaps installed on this system but not in {snaps_file}',
    ['Choose which snaps to remove from the system',
     f'and which ones to add to the {snaps_file} file.'],
    'Remove this snap',
    snap_remove,
    'Failed to remove snap')
spit(snaps_file, json.dumps(snaps(), indent=2, sort_keys=True) + '\n')
