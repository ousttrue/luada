import platform
import os
import io
from invoke import task, Context
import pathlib

HERE = pathlib.Path(__file__).absolute().parent
LUAJIT_DIR = HERE / 'LuaJIT/src'
LUA_BIN = LUAJIT_DIR / 'luajit.exe'

VCVARS_BAT = pathlib.Path(
    "C:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\BuildTools\\VC\\Auxiliary\\Build\\vcvars64.bat"
)


def get_cmake() -> pathlib.Path:
    if platform.system() == "Windows":
        for p in os.environ['PATH'].split(';'):
            if p:
                p = pathlib.Path(p)
                if p.exists():
                    cmake = p / 'cmake.exe'
                    if cmake.exists():
                        return cmake

        cmake = pathlib.Path("C:/Program Files/CMake/bin/cmake.exe")
        if cmake.exists():
            return cmake

        raise FileNotFoundError('cmake.exe')

    else:
        raise NotImplementedError()


def commandline(exe: pathlib.Path, *args: str):
    cmd = str(exe)
    if ' ' in cmd:
        cmd = f'"{cmd}"'
    return f'{cmd} {" ".join(args)}'


@task
def build(c):
    # type: (Context) -> None
    '''
    build luajit in luajitffi
    '''
    if not VCVARS_BAT.exists():
        raise Exception('no vcvars64.bat')

    with c.cd(LUAJIT_DIR):
        c.run(f'{os.environ["COMSPEC"]} /K "{VCVARS_BAT}"',
              in_stream=io.StringIO("msvcbuild.bat\r\nexit\r\n')"))
