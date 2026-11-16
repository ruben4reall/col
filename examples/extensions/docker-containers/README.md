# Docker Containers

How many Docker containers run, with the first three named, as a widget. While Docker itself is not running, the
widget goes.

- **Shows**: a widget in the island's Widgets place.
- **Needs**: Docker Desktop, OrbStack, Colima or any engine the `docker` command reaches.
- **Runs**: every minute (`docker ps`).

```sh
colctl extensions install examples/extensions/docker-containers --on
```
