#!/usr/bin/env python3
from setuptools import setup

setup(
    name="python_ki_hydra",
    version="1.0.0",
    description="A Unified API for all Python AI Services from IT's JOINTLY",
    packages=["python_ki_hydra"],
    install_requires=[
        d for d in open("requirements.txt").readlines() if not d.startswith("--")
    ],
    package_dir={"": "src"},
    entry_points={"console_scripts": ["python_ki_hydra = python_ki_hydra.main:main"]},
)
