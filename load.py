import pkg_resources

# Get all installed packages
installed_packages = pkg_resources.working_set

# Create a requirements.txt file
with open('req.txt', 'w') as f:
    for package in installed_packages:
        f.write(f"{package.project_name}\n")
