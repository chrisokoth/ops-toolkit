"""
Utility functions for YeleDeploy
"""

from colorama import Fore, Style
import subprocess
import os

def print_status(message):
    """Print status message in green"""
    print(f"{Fore.GREEN}[INFO]{Style.RESET_ALL} {message}")

def print_warning(message):
    """Print warning message in yellow"""
    print(f"{Fore.YELLOW}[WARNING]{Style.RESET_ALL} {message}")

def print_error(message):
    """Print error message in red"""
    print(f"{Fore.RED}[ERROR]{Style.RESET_ALL} {message}")

def print_header(message):
    """Print header message in blue"""
    print(f"{Fore.BLUE}{'=' * 50}{Style.RESET_ALL}")
    print(f"{Fore.BLUE}{message}{Style.RESET_ALL}")
    print(f"{Fore.BLUE}{'=' * 50}{Style.RESET_ALL}")

def command_exists(command):
    """Check if command exists in system"""
    try:
        subprocess.run(["which", command], check=True, capture_output=True)
        return True
    except subprocess.CalledProcessError:
        return False

def run_command(command, check=True, shell=False, **kwargs):
    """Run system command with error handling"""
    try:
        if shell:
            result = subprocess.run(command, shell=True, check=check, **kwargs)
        else:
            result = subprocess.run(command, check=check, **kwargs)
        return result
    except subprocess.CalledProcessError as e:
        raise Exception(f"Command failed: {' '.join(command) if isinstance(command, list) else command}")

def create_directory(path, mode=0o755, sudo=False):
    """Create directory with proper permissions"""
    if sudo:
        run_command(["sudo", "mkdir", "-p", path])
        run_command(["sudo", "chmod", oct(mode)[2:], path])
    else:
        os.makedirs(path, mode=mode, exist_ok=True)

def generate_secret_key():
    """Generate Django secret key"""
    from django.core.management.utils import get_random_secret_key
    return get_random_secret_key()

def validate_domain(domain):
    """Basic domain validation"""
    import re
    pattern = r'^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$|^[a-zA-Z0-9]+\.[a-zA-Z]{2,}$'
    if not re.match(pattern, domain):
        raise ValueError(f"Invalid domain format: {domain}")
    return True

def get_project_path(project_dir):
    """Get full project path"""
    return f"/home/ubuntu/{project_dir}"

def get_venv_path(project_path):
    """Get virtual environment path"""
    return f"{project_path}/venv"