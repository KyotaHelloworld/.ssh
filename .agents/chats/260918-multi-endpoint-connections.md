# Chat: Multiple SSH routes per machine

- kyota requested support for one machine reachable through multiple IP paths,
  especially IPv6, IPv4, and VPN routes.
- Each route should be independently selectable as an SSH alias while reusing
  the existing machine key.
- The chosen workflow adds `<machine>-<route>` as a separate ignored config
  fragment and never modifies or copies the existing private key.
