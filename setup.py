#!/usr/bin/env python3
from setuptools import setup
from src.python_kidra._version import __version__

setup(
    name="python_kidra",
    version=__version__,
    description="A Unified API for all Python AI Services from IT's JOINTLY",
    packages=["python_kidra"],
    install_requires=[
        d for d in open("requirements.txt").readlines() if not d.startswith("--")
    ],
    package_dir={"": "src"},
    entry_points={"console_scripts": ["python-kidra = python_kidra.__main__:main"]},
)
