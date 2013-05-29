#!/usr/bin/env python

"""

The master setup.py file for py_gnome

you should be able to run :

python setup.py develop

to build and install the whole thing in development mode

(it will only work right with distribute, not setuptools)

All the shared C++ code is compiled with  basic_types.pyx

It needs to be imported before any other extensions
(which happens in the gnome.__init__.py file)

"""

## NOTE: this works with "distribute" package, but not with setuptools.
import os
import glob
import shutil
import sys

# to support "develop" mode:
from setuptools import setup, find_packages

from distutils.extension import Extension
from Cython.Distutils import build_ext

import numpy as np

if "clean" in "".join(sys.argv[1:]):
    target = 'clean'
else:
    target = 'build'

if "cleanall" in "".join(sys.argv[1:]):
    target = 'clean'

    if sys.platform == 'win32':
        rm_extensions = ['dll', 'pyd', 'cpp']
    else:
        rm_extensions = ['so', 'pyd', 'cpp']

    rm_files = [os.path.join('gnome','cy_gnome','cy_*.%s' % e)
                for e in rm_extensions]

    for files_ in rm_files:
        for file_ in glob.glob(files_):
            print "Deleting auto-generated files: {0}".format(file_)
            os.remove(file_)

    rm_dir = ['pyGnome.egg-info', 'build']
    for dir_ in rm_dir:
        print "Deleting auto-generated directory: {0}".format(dir_)
        try:
            shutil.rmtree(dir_)
        except OSError as e:
            print e

    # this is what distutils understands
    sys.argv[1] = 'clean'


# only for windows
if "debug" in "".join(sys.argv[2:]):
    config = 'debug'
else:
    config = 'release'    # only used by windows


if sys.argv.count(config) != 0:
    sys.argv.remove(config)


# for the mac -- forcing 32 bit only builds
if sys.platform == 'darwin':
    #Setting this should force only 32 bit intel build
    os.environ['ARCHFLAGS'] = "-arch i386"


# the cython extensions to build -- each should correspond to a *.pyx file
extension_names = ['cy_mover',
                   'cy_helpers',
                   'cy_wind_mover',
                   'cy_cats_mover',
                   'cy_gridcurrent_mover',
                   'cy_gridwind_mover',
                   'cy_ossm_time',
                   'cy_random_mover',
                   'cy_random_vertical_mover',
                   'cy_land_check',
                   'cy_grid_map',
                   'cy_shio_time',
                   ]

cpp_files = ['RectGridVeL_c.cpp',
             'MemUtils.cpp',
             'Mover_c.cpp',
             'Replacements.cpp',
             'ClassID_c.cpp',
             'Random_c.cpp',
             'TimeValuesIO.cpp',
             'GEOMETRY.cpp',
             'OSSMTimeValue_c.cpp',
             'TimeValue_c.cpp',
             'RectUtils.cpp',
             'WindMover_c.cpp',
             'CompFunctions.cpp',
             #'CMYLIST.cpp',
             #'GEOMETR2.cpp',
             'StringFunctions.cpp',
             'OUTILS.cpp',
             #'NetCDFMover_c.cpp',
             'CATSMover_c.cpp',
             'CurrentMover_c.cpp',
             'ShioTimeValue_c.cpp',
             'ShioHeight.cpp',
             'TriGridVel_c.cpp',
             'DagTree.cpp',
             'DagTreeIO.cpp',
             'ShioCurrent1.cpp',
             'ShioCurrent2.cpp',
             'GridCurrentMover_c.cpp',
             'GridWindMover_c.cpp',
             'TimeGridVel_c.cpp',
             'TimeGridWind_c.cpp',
             'MakeTriangles.cpp',
             'MakeDagTree.cpp',
             'GridMap_c.cpp',
             'GridMapUtils.cpp',
             'RandomVertical_c.cpp',
             ]


cpp_code_dir = os.path.join('..', 'lib_gnome')
cpp_files = [os.path.join(cpp_code_dir, f) for f in cpp_files]

## setting the "pyGNOME" define so that conditional compilation
## in the cpp files is done right.
macros = [('pyGNOME', 1), ]

## Build the extension objects
compile_args = []
extensions = []

lib = []
libdirs = []
static_lib_files = []
link_args = []

# List of include directories for cython code.
# append to this list as needed for each platform
include_dirs = [cpp_code_dir, np.get_include(), '.']


# build cy_basic_types along with lib_gnome so we can use distutils
# for building everything
# and putting it in the correct place for linking.
# cy_basic_types needs to be imported before any other extensions.
# This is being done in the gnome/cy_gnome/__init__.py

if sys.platform == "darwin":
    architecture = os.environ['ARCHFLAGS'].split()[1]
    include_dirs.append('../third_party/%s/include' % architecture)
    third_party_lib_dir = '../third_party/%s/lib' % architecture

    static_lib_names = ('hdf5', 'hdf5_hl', 'netcdf', 'netcdf_c++4')
    static_lib_files = [os.path.join(third_party_lib_dir, 'lib%s.a' % l)
                        for l in static_lib_names]

    basic_types_ext = Extension(r'gnome.cy_gnome.cy_basic_types',
            ['gnome/cy_gnome/cy_basic_types.pyx'] + cpp_files,
            language='c++',
            define_macros=macros,
            extra_compile_args=compile_args,
            extra_link_args=['-lz', '-lcurl'],
            extra_objects=static_lib_files,
            include_dirs=include_dirs,
            )

    extensions.append(basic_types_ext)
    static_lib_files = []


elif sys.platform == "win32":
    # Distutils normally only works with VS2008.
    # this is to trick it into seeing VS2010 or VS2012
    # We will prefer VS2012, then VS2010
    if 'VS110COMNTOOLS' in os.environ:
        os.environ['VS90COMNTOOLS'] = os.environ['VS110COMNTOOLS']
    elif 'VS100COMNTOOLS' in os.environ:
        os.environ['VS90COMNTOOLS'] = os.environ['VS100COMNTOOLS']

    # build our compile arguments
    macros.append(('_EXPORTS', 1))
    macros.append(('_CRT_SECURE_NO_WARNINGS', 1))
    compile_args = ['/EHsc']
    include_dirs.append(os.path.join('..', 'third_party_lib', 'netcdf-4.3'))

    # build our linking arguments
    netcdf_dir = os.path.join('..', 'third_party_lib', 'netcdf-4.3',
                              'win32', 'i386')
    libdirs.append(netcdf_dir)
    link_args.append('/MANIFEST')

    static_lib_names = ('netcdf',)
    static_lib_files = [os.path.join(netcdf_dir, '%s.lib' % l)
                        for l in static_lib_names]

    basic_types_ext = Extension(r'gnome.cy_gnome.cy_basic_types',
            [r'gnome\cy_gnome\cy_basic_types.pyx'] + cpp_files,
            language='c++',
            define_macros=macros,
            extra_compile_args=compile_args,
            library_dirs=libdirs,
            extra_link_args=link_args,
            extra_objects=static_lib_files,
            include_dirs=include_dirs,
            )

    extensions.append(basic_types_ext)

    # we will reference this library when building all other extensions
    static_lib_files = [os.path.join('build', 'temp.win32-2.7', 'Release',
                                     'gnome', 'cy_gnome',
                                     'cy_basic_types.lib')]
    libdirs = []


#
### the "master" extension -- of the extra stuff,
### so the whole C++ lib will be there for the others
#

# TODO: the extensions below look for the shared object lib_gnome in
# './build/lib.macosx-10.3-fat-2.7/gnome' and './gnome'
# Ideally, we should build lib_gnome first and move it
# to wherever we wish to link from .. currently the build_ext and develop
# will find and link to the object in different places.

for mod_name in extension_names:
    cy_file = os.path.join("gnome/cy_gnome", mod_name + ".pyx")
    extensions.append(Extension('gnome.cy_gnome.' + mod_name,
                                 [cy_file],
                                 language="c++",
                                 define_macros=macros,
                                 extra_compile_args=compile_args,
                                 extra_link_args=link_args,
                                 libraries=lib,
                                 library_dirs=libdirs,
                                 extra_objects=static_lib_files,
                                 include_dirs=include_dirs,
                                 )
                       )


setup(name='pyGnome',
      version='alpha',
      requires=['numpy'],
      cmdclass={'build_ext': build_ext},
      packages=find_packages(exclude=['gnome.deprecated']),
      ext_modules=extensions
     )
