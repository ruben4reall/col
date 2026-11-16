# GitHub Actions

The last workflow run of a repository, beside the camera, while it runs and for a minute after it ends: Running in
orange, Passed in green, Failed in red as an alert.

- **Shows**: a live activity in the closed island.
- **Needs**: the [GitHub CLI](https://cli.github.com) (`gh`), signed in.
- **Runs**: every minute (`gh run list`).

Set `REPO_DIR` at the top of `status.sh` to your checkout, then:

```sh
colctl extensions install examples/extensions/github-actions --on
```
