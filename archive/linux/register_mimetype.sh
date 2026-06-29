#!/bin/bash

# Constants
MIME_TYPE="application/x-bview"
FILE_EXT="*.bview"
COMMENT="BioView Experiment Files"
XML_FILE="bioview.xml"

echo "Creating MIME XML definition..."

# Create the XML file following freedesktop spec 
cat > "$XML_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
    <mime-type type="$MIME_TYPE">
        <comment>$COMMENT</comment>
        <glob pattern="$FILE_EXT"/>
        <icon name="utilities-terminal"/>
    </mime-type>
</mime-info>
EOF

# Install the MIME type for the current user
echo "Registering file types..."
xdg-mime install --mode system "$XML_FILE" # should I use --mode user? 
update-mime-database ~/.local/share/mime

# Clean up
rm "$XML_FILE"

echo "BioView has been successfully configured to open .bview files!"
# echo "Ensure your .desktop file is in ~/.local/share/applications/ and run 'update-desktop-database ~/.local/share/applications' to finish."
