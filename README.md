# Stencyl Repository Manager

Initial setup:
```
cd /my/repository/home/
srm setup
```

Add an extension/version to the repository:

`srm add /path/to/extension.jar /path/to/changeset/file`
`srm add /path/to/engine-extension/folder /path/to/changeset/file engine.extension.id`

View extensions added to repository:

`srm list toolset`

View extension versions:

`srm versions toolset extension.id`

Get path for extension version or resource:

`srm path toolset extension.id 1.0.0`
`srm path toolset extension.id icon`
`srm path toolset extension.id info`
