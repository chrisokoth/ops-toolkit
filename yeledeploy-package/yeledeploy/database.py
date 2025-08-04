"""
Database management module for YeleDeploy
"""

import psycopg2
from psycopg2 import sql
import subprocess
from .utils import print_status, print_error, print_warning

class DatabaseManager:
    def __init__(self, db_name, db_password):
        self.db_name = db_name
        self.db_password = db_password
        self.db_user = "postgres"
        self.db_host = "localhost"
        self.db_port = "5432"
    
    def setup_postgresql(self):
        """Setup PostgreSQL service and configuration"""
        print_status("Starting PostgreSQL service...")
        try:
            subprocess.run(["sudo", "systemctl", "start", "postgresql"], check=True)
            subprocess.run(["sudo", "systemctl", "enable", "postgresql"], check=True)
        except subprocess.CalledProcessError:
            raise Exception("Failed to start PostgreSQL service")
    
    def database_exists(self):
        """Check if database already exists"""
        try:
            # Connect to postgres database to check if target database exists
            conn = psycopg2.connect(
                host=self.db_host,
                port=self.db_port,
                user=self.db_user,
                password=self.db_password,
                database="postgres"
            )
            conn.autocommit = True
            cursor = conn.cursor()
            
            # Check if database exists
            cursor.execute(
                "SELECT 1 FROM pg_database WHERE datname = %s",
                (self.db_name,)
            )
            exists = cursor.fetchone() is not None
            
            cursor.close()
            conn.close()
            return exists
            
        except psycopg2.Error:
            # If we can't connect, assume database doesn't exist
            return False
    
    def create_database(self):
        """Create database only if it doesn't exist"""
        print_status(f"Checking if database '{self.db_name}' exists...")
        
        if self.database_exists():
            print_warning(f"Database '{self.db_name}' already exists. Skipping creation.")
            return True
        
        print_status(f"Creating database '{self.db_name}'...")
        
        try:
            # First, set the postgres user password
            subprocess.run([
                "sudo", "-u", "postgres", "psql", "-c",
                f"ALTER USER postgres WITH PASSWORD '{self.db_password}';"
            ], check=True, capture_output=True)
            
            # Create the database
            subprocess.run([
                "sudo", "-u", "postgres", "psql", "-c",
                f'CREATE DATABASE "{self.db_name}";'
            ], check=True, capture_output=True)
            
            # Grant privileges
            subprocess.run([
                "sudo", "-u", "postgres", "psql", "-c",
                f'GRANT ALL PRIVILEGES ON DATABASE "{self.db_name}" TO postgres;'
            ], check=True, capture_output=True)
            
            # Grant create database permission
            subprocess.run([
                "sudo", "-u", "postgres", "psql", "-c",
                "ALTER USER postgres CREATEDB;"
            ], check=True, capture_output=True)
            
            print_status(f"Database '{self.db_name}' created successfully!")
            return True
            
        except subprocess.CalledProcessError as e:
            raise Exception(f"Failed to create database: {e}")
    
    def configure_postgresql(self):
        """Configure PostgreSQL settings"""
        print_status("Configuring PostgreSQL settings...")
        
        try:
            # Get PostgreSQL version
            result = subprocess.run([
                "sudo", "-u", "postgres", "psql", "-t", "-c", "SELECT version();"
            ], capture_output=True, text=True, check=True)
            
            # Extract version number
            version_line = result.stdout.strip()
            pg_version = version_line.split()[1].split('.')[0]
            pg_config_path = f"/etc/postgresql/{pg_version}/main"
            
            # Update postgresql.conf
            subprocess.run([
                "sudo", "sed", "-i",
                "s/#listen_addresses = 'localhost'/listen_addresses = 'localhost'/",
                f"{pg_config_path}/postgresql.conf"
            ], check=True)
            
            # Update pg_hba.conf for md5 authentication
            subprocess.run([
                "sudo", "sed", "-i",
                "s/local   all             postgres                                peer/local   all             postgres                                md5/",
                f"{pg_config_path}/pg_hba.conf"
            ], check=True)
            
            # Restart PostgreSQL
            subprocess.run(["sudo", "systemctl", "restart", "postgresql"], check=True)
            
        except subprocess.CalledProcessError:
            print_warning("Could not update PostgreSQL configuration files")
    
    def test_connection(self):
        """Test database connection"""
        print_status("Testing database connection...")
        
        try:
            conn = psycopg2.connect(
                host=self.db_host,
                port=self.db_port,
                user=self.db_user,
                password=self.db_password,
                database=self.db_name
            )
            
            cursor = conn.cursor()
            cursor.execute("SELECT 1;")
            cursor.fetchone()
            cursor.close()
            conn.close()
            
            print_status("Database connection successful!")
            return True
            
        except psycopg2.Error as e:
            raise Exception(f"Database connection failed: {e}")
    
    def setup(self):
        """Complete database setup process"""
        self.setup_postgresql()
        self.configure_postgresql()
        self.create_database()
        self.test_connection()