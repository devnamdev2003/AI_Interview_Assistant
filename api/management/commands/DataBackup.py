import subprocess

help_message = 'Backup PostgreSQL database'

def handle():
    # Define your database connection details
    db_url = 'postgresql://postgres:!QAZ2wsx3edc@localhost:5432/aiia_localdb?sslmode=require'
    # db_url = 'postgresql://co71u4:xau_lH9jYxJQXOcgjzftu1vXjISIuzDOSvvmo@us-east-1.sql.xata.sh/aiia_testdb:main?sslmode=requir'
    # Extract database name for the backup filename
    db_name = db_url.split('/')[-1].split(':')[0]
    backup_file = f"{db_name}_backup.sql"
    
    # Create the backup command without extra quotes
    command = f"pg_dump {db_url} > {backup_file}"
    
    # Execute the backup command
    try:
        subprocess.run(command, shell=True, check=True)
        print(f'Successfully backed up database to {backup_file}')
    except subprocess.CalledProcessError as e:
        print(f'Error during backup: {e}')

if __name__ == "__main__":
    handle()
