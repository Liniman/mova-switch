# Security

MovaSwitch reads every key you press, so a security bug in it matters.

## Report a vulnerability

Do not open a public issue. On the repository page, open **Security > Report a vulnerability** and describe the problem there. The report stays private until a fix is released.

## What MovaSwitch does with your typing

- It makes no network connections.
- It keeps the current word and up to three short words before it in memory. It writes none of them to disk.
- It saves only your settings and your never-convert list.
- It does nothing while macOS Secure Input is on, which covers password fields.

A change that breaks one of these rules is a vulnerability. Report it the same way.
