# Chat: SSH key and config generator

- kyota wants the existing key-generation commands and scripts cleaned up.
- A new key command should also generate every safely derivable part of its
  matching `config.d` fragment.
- `keys/sample/id` is an intentional unused fixture and must remain tracked.
- The implementation should reject unsafe names, avoid passphrases in command
  arguments, preserve existing files, and keep private config fragments ignored.
- kyota accepted the validated implementation for local master integration.
