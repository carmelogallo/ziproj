# fish completion for ziproj - https://github.com/carmelogallo/ziproj

complete -c ziproj -f -a '(__fish_complete_directories)'

complete -c ziproj -s n -l dry-run -d 'List and scan, write nothing'
complete -c ziproj -s r -l redact -d 'Replace detected secrets with REDACTED in the zip'
complete -c ziproj -s a -l ai -d 'Also drop images, PDFs, fonts, audio and video'
complete -c ziproj -s x -l exclude -r -F -d 'Exclude a file, folder or glob'
complete -c ziproj -s o -l out -x -a '(__fish_complete_directories)' -d 'Folder for the zip'
complete -c ziproj -s f -l force -d 'Write the zip even with secrets in plain text'
complete -c ziproj -l no-gitleaks -d 'Do not use gitleaks, and do not ask'
complete -c ziproj -l no-open -d 'Do not reveal the zip in Finder or the file manager'
complete -c ziproj -s h -l help -d 'Show help'
complete -c ziproj -s V -l version -d 'Show the version'
