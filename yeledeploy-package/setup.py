from setuptools import setup, find_packages
import os

# Read the contents of README file
this_directory = os.path.abspath(os.path.dirname(__file__))
with open(os.path.join(this_directory, 'README.md'), encoding='utf-8') as f:
    long_description = f.read()

setup(
    name="yeledeploy",
    version="1.0.1",  # Increment version for updates
    author="Your Name",
    author_email="your.email@example.com",
    description="Automated Django deployment tool for EC2 with PostgreSQL, Nginx, and Gunicorn",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/chrisokoth/ops-toolkit/yeledeploy",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: POSIX :: Linux",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Build Tools",
        "Topic :: System :: Installation/Setup",
    ],
    python_requires=">=3.8",
    install_requires=[
        "click>=8.0.0",
        "colorama>=0.4.0",
        "psycopg2-binary>=2.9.0",
        "jinja2>=3.0.0",
        "django>=3.2.0",
    ],
    entry_points={
        "console_scripts": [
            "yeledeploy=yeledeploy.cli:main",
        ],
    },
    include_package_data=True,
    package_data={
        "yeledeploy": ["templates/*"],
    },
    keywords="django deployment ec2 nginx gunicorn postgresql automation",
    project_urls={
        "Bug Reports": "https://github.com/chrisokoth/ops-toolkit/yeledeploy/issues",
        "Source": "https://github.com/chrisokoth/ops-toolkit/yeledeploy",
        "Documentation": "https://github.com/chrisokoth/ops-toolkit/yeledeploy#readme",
    },
)