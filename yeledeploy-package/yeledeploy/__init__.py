"""
YeleDeploy - Django EC2 Auto Deployment Tool

A Python package for automating Django application deployment on EC2 
with PostgreSQL, Nginx, and Gunicorn.
"""

__version__ = "1.0.0"
__author__ = "Chris Okoth"
__email__ = "chris@yelegroup.africa"

from .deployment import DjangoDeployer
from .database import DatabaseManager
from .cli import main

__all__ = ['DjangoDeployer', 'DatabaseManager', 'main']