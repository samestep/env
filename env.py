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
                ppas.append(match.group(1))
    return ppas


def ppas():
    """Return the set of PPA's on the system."""
    return set([ppa for file in source_lists() for ppa in file_ppas(file)])


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


def slurp(path):
    """Return contents of file at path."""
    with open(path) as f:
        return f.read()


def spit(path, content):
    """Write content to file at path."""
    with open(path, 'w') as f:
        f.write(content)


spit('ppas.json', json.dumps(sorted(ppas()), indent=2) + '\n')
spit('apt_packages.json', json.dumps(sorted(apt_packages()), indent=2) + '\n')
spit('snaps.json', json.dumps(snaps(), indent=2, sort_keys=True) + '\n')
