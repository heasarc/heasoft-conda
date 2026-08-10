#!/usr/bin/env python3

import os
import argparse
import json
import subprocess


sep_line = '-'*30


def get_config(config_file='config.json'):
    """Read the config file that has the package information

    Parameters
    config: str
        file name of the config file.
        It should in the same location as this script.

    """

    script_dir = os.path.abspath(os.path.dirname(__file__))

    if not os.path.exists(f'{script_dir}/{config_file}'):
        raise FileExistsError(
            f'No config file {config_file} found in {script_dir}')
    with open(f'{script_dir}/{config_file}') as fp:
        config = json.load(fp)
    return config


def _run_cmd(cmd, dryrun=False):

    print('\n' + sep_line)
    print(cmd)
    print(sep_line + '\n')
    if not dryrun:
        subprocess.call(cmd, shell=True)


def pack_files(package, version, dev, config, dryrun):
    """Pack the requested package files to a tar file

    Parameters:
    -----------
    package: str
        package name from the config file
    version: str
        package version
    dev: bool
        If true, use the dev-root location instead of root
    config: dict
        dict of the config information
    dryrun: bool
        If True, print messages without doing the run

    """
    if package is None:
        raise ValueError(f'No package given: package = {package}')
    if version is None:
        raise ValueError(f'No version given: version = {version}')

    if package not in config['packages']:
        raise KeyError(f'No entry for {package} in the config file')

    pconfig = config['packages'][package]

    # handle the case of a link to another package
    if 'link' in pconfig:
        linked_packaged = pconfig['link'].format(version=version)
        if not dryrun and not os.path.exists(f'{linked_packaged}.tar.gz'):
            raise ValueError(
                f'Package {package} is linked to {linked_packaged}, but '
                f'no {linked_packaged}.tar.gz file found!'
            )
        else:
            cmd = f'ln -s {linked_packaged}.tar.gz {package}-{version}.tar.gz'
            _run_cmd(cmd, dryrun)
    else:

        if dev:
            rootdir = pconfig.get(
                'dev-root',
                '/software/lheasoft/conda'
            )
        else:
            rootdir = pconfig.get(
                'root',
                '/FTP/software/lheasoft/lheasoft{version}/heasoft-{version}"'
            )
        rootdir = rootdir.format(package=package, version=version)
        if not os.path.exists(rootdir) and not dryrun:
            raise ValueError(
                (f'ERROR: The given or default root dir for {package}: '
                 f'{rootdir} does not exist')
            )
        include = pconfig.get('include', ['*'])
        if isinstance(include, str):
            include = [include]

        exclude = pconfig.get('exclude', [])
        if isinstance(exclude, str):
            exclude = [exclude]

        print('\n' + sep_line)
        print('rootdir: ', rootdir)
        print('include: ', include)
        print('exclude: ', exclude)
        print(sep_line + '\n')

        cwd = os.getcwd()
        basedir = os.path.basename(rootdir)
        tarfile = f'{cwd}/{package}-{version}.tar.gz'
        cmd = (
            f'tar -czf {tarfile} ' +
            (' '.join([f'--exclude="{basedir}/{ex}"' for ex in exclude])) +
            ' ' +
            (' '.join([f'{basedir}/{inc}' for inc in include]))
        )
        os.chdir(f'{rootdir}/..')
        _run_cmd(cmd, dryrun)
        cmd = f'sha256sum {tarfile} >> {cwd}/shasums.txt'
        _run_cmd(cmd, dryrun)
        os.chdir(cwd)


if __name__ == '__main__':

    parser = argparse.ArgumentParser(
        description='generate conda source tar files')

    parser.add_argument(
        '-p', '--package',
        help='Package name. e.g. heasoft; ignored if --all is used'
    )

    parser.add_argument(
        '-v', '--version', help='Package version. e.g. 6.34'
    )

    parser.add_argument(
        '--dev', action='store_true', default=False,
        help='Use dev-root to locate the package to root'
    )

    parser.add_argument(
        '-a', '--all', action='store_true', default=False,
        help='Generate all packages. If true, ignore -p'
    )

    parser.add_argument(
        '--config', help='Config file', default='package_config.json'
    )

    parser.add_argument(
        '--dryrun', help='Dry run', action='store_true', default=False,
    )

    # parse arguments
    args = parser.parse_args()

    # read the config file
    config = get_config(args.config)

    if args.all:
        # find all packages
        packages = config['packages'].keys()

        for package in packages:
            pack_files(package, args.version, args.dev, config, args.dryrun)
    else:
        # Pack the files
        pack_files(args.package, args.version, args.dev, config, args.dryrun)
