#!/usr/bin/env python

from distutils.core import setup

setup(
    name = 'RMI',
    version = '0.01',
    description = 'Remote Method Invocation',
    author = 'Scott Smith',
    author_email = 'sakoht@cpan.org',
    url = 'https://github.com/sakoht/RMI/',
    package_dir = {'': 'lib'},
    #py_modules = ['RMI'],
    packages = ['RMI']
)

