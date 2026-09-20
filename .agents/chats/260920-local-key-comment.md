# Chat: Local public-key comment

- kyota pointed out that a public-key comment should identify the PC that
  created the key, not the remote login user or destination.
- Future keys should use the local `user@hostname` comment by default while
  retaining an explicit custom-comment option.
- Existing keys must not be modified.
