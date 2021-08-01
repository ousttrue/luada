# LuaDA

Lua Debug Adapter

[Debug Adapter Protocol]<https://microsoft.github.io/debug-adapter-protocol/> implementation.

## TODO

* [ ] request: disconnect
* [ ] launch: env
* [ ] error handling: extension(exe not found...)
* [ ] error handling: debug adapter

## build vsix

```
$ npx vsce package
```

## build luajit

* require python3
* require vc2019

```
$ pip install invoke
$ invoke build

$ LuaJIT/src/luajit.exe
```
