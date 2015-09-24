# Stencyl Repository Manager

Initial setup:
```
cd /my/repository/home/
stencylrm setup
```

Add an extension/version to the repository:

`stencylrm add /path/to/extension.jar -c "Changes."`

View extensions added to repository:

`stencylrm list toolset`

View extension versions:

`stencylrm versions toolset extension.id`

Get path for extension version:

`stencylrm path toolset extension.id 1.0.0`
