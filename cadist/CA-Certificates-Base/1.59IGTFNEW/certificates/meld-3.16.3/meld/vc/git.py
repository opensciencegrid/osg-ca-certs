# -*- coding: utf-8 -*-
# Copyright (C) 2002-2005 Stephen Kennedy <stevek@gnome.org>
# Copyright (C) 2005 Aaron Bentley <aaron.bentley@utoronto.ca>
# Copyright (C) 2007 José Fonseca <j_r_fonseca@yahoo.co.uk>
# Copyright (C) 2010-2015 Kai Willadsen <kai.willadsen@gmail.com>

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.

# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import errno
import os
import re
import shutil
import stat
import subprocess
import sys
import StringIO
import tempfile
from collections import defaultdict

from meld.conf import _, ngettext

from . import _vc


NULL_SHA = "0000000000000000000000000000000000000000"


class Vc(_vc.Vc):

    CMD = "git"
    NAME = "Git"
    VC_DIR = ".git"

    GIT_DIFF_FILES_RE = ":(\d+) (\d+) ([a-z0-9]+) ([a-z0-9]+) ([XADMTU])\t(.*)"
    DIFF_RE = re.compile(GIT_DIFF_FILES_RE)

    conflict_map = {
        # These are the arguments for git-show
        # CONFLICT_MERGED has no git-show argument unfortunately.
        _vc.CONFLICT_BASE: 1,
        _vc.CONFLICT_LOCAL: 2,
        _vc.CONFLICT_REMOTE: 3,
    }

    state_map = {
        "X": _vc.STATE_NONE,      # Unknown
        "A": _vc.STATE_NEW,       # New
        "D": _vc.STATE_REMOVED,   # Deleted
        "M": _vc.STATE_MODIFIED,  # Modified
        "T": _vc.STATE_MODIFIED,  # Type-changed
        "U": _vc.STATE_CONFLICT,  # Unmerged
    }

    @classmethod
    def is_installed(cls):
        try:
            proc = _vc.popen([cls.CMD, '--version'])
            assert proc.read().startswith('git version')
            return True
        except Exception:
            return False

    @classmethod
    def check_repo_root(self, location):
        # Check exists instead of isdir, since .git might be a git-file
        return os.path.exists(os.path.join(location, self.VC_DIR))

    def get_commits_to_push_summary(self):
        branch_refs = self.get_commits_to_push()
        unpushed_branches = len([v for v in branch_refs.values() if v])
        unpushed_commits = sum(len(v) for v in branch_refs.values())
        if unpushed_commits:
            if unpushed_branches > 1:
                # Translators: First %s is replaced by translated "%d unpushed
                # commits", second %s is replaced by translated "%d branches"
                label = _("%s in %s") % (
                    ngettext("%d unpushed commit", "%d unpushed commits",
                             unpushed_commits) % unpushed_commits,
                    ngettext("%d branch", "%d branches",
                             unpushed_branches) % unpushed_branches)
            else:
                # Translators: These messages cover the case where there is
                # only one branch, and are not part of another message.
                label = ngettext("%d unpushed commit", "%d unpushed commits",
                                 unpushed_commits) % (unpushed_commits)
        else:
            label = ""
        return label

    def run(self, *args):
        cmd = (self.CMD,) + args
        return subprocess.Popen(cmd, cwd=self.location, stdout=subprocess.PIPE)

    def get_commits_to_push(self):
        proc = self.run(
            "for-each-ref", "--format=%(refname:short) %(upstream:short)",
            "refs/heads")
        branch_remotes = proc.stdout.read().split("\n")[:-1]

        branch_revisions = {}
        for line in branch_remotes:
            try:
                branch, remote = line.split()
            except ValueError:
                continue

            proc = self.run("rev-list", branch, "^" + remote)
            revisions = proc.stdout.read().split("\n")[:-1]
            branch_revisions[branch] = revisions
        return branch_revisions

    def get_files_to_commit(self, paths):
        files = []
        for p in paths:
            if os.path.isdir(p):
                entries = self._get_modified_files(p)
                names = [self.DIFF_RE.search(e).groups()[5] for e in entries]
                files.extend(names)
            else:
                files.append(os.path.relpath(p, self.root))
        return sorted(list(set(files)))

    def get_commit_message_prefill(self):
        commit_path = os.path.join(self.root, ".git", "MERGE_MSG")
        if os.path.exists(commit_path):
            # If I have to deal with non-ascii, non-UTF8 pregenerated commit
            # messages, I'm taking up pig farming.
            with open(commit_path) as f:
                message = f.read().decode('utf8')
            return "\n".join(
                (l for l in message.splitlines() if not l.startswith("#")))
        return None

    def commit(self, runner, files, message):
        command = [self.CMD, 'commit', '-m', message]
        runner(command, files, refresh=True, working_dir=self.root)

    def update(self, runner):
        command = [self.CMD, 'pull']
        runner(command, [], refresh=True, working_dir=self.root)

    def push(self, runner):
        command = [self.CMD, 'push']
        runner(command, [], refresh=True, working_dir=self.root)

    def add(self, runner, files):
        command = [self.CMD, 'add']
        runner(command, files, refresh=True, working_dir=self.root)

    def remove(self, runner, files):
        command = [self.CMD, 'rm', '-r']
        runner(command, files, refresh=True, working_dir=self.root)

    def revert(self, runner, files):
        exists = [f for f in files if os.path.exists(f)]
        missing = [f for f in files if not os.path.exists(f)]
        if exists:
            command = [self.CMD, 'checkout']
            runner(command, exists, refresh=True, working_dir=self.root)
        if missing:
            command = [self.CMD, 'checkout', 'HEAD']
            runner(command, missing, refresh=True, working_dir=self.root)

    def resolve(self, runner, files):
        command = [self.CMD, 'add']
        runner(command, files, refresh=True, working_dir=self.root)

    def remerge_with_ancestor(self, local, base, remote):
        """Reconstruct a mixed merge-plus-base file

        This method re-merges a given file to get diff3-style conflicts
        which we can then use to get a file that contains the
        pre-merged result everywhere that has no conflict, and the
        common ancestor anywhere there *is* a conflict.
        """
        proc = self.run("merge-file", "-p", "--diff3", local, base, remote)
        vc_file = StringIO.StringIO(
            _vc.base_from_diff3(proc.stdout.read()))

        prefix = 'meld-tmp-%s-' % _vc.CONFLICT_MERGED
        with tempfile.NamedTemporaryFile(prefix=prefix, delete=False) as f:
            shutil.copyfileobj(vc_file, f)

        return f.name, True

    def get_path_for_conflict(self, path, conflict):
        if not path.startswith(self.root + os.path.sep):
            raise _vc.InvalidVCPath(self, path, "Path not in repository")

        if conflict == _vc.CONFLICT_MERGED:
            # Special case: no way to get merged result from git directly
            local, _ = self.get_path_for_conflict(path, _vc.CONFLICT_LOCAL)
            base, _ = self.get_path_for_conflict(path, _vc.CONFLICT_BASE)
            remote, _ = self.get_path_for_conflict(path, _vc.CONFLICT_REMOTE)

            if not (local and base and remote):
                raise _vc.InvalidVCPath(self, path,
                                        "Couldn't access conflict parents")

            filename, is_temp = self.remerge_with_ancestor(local, base, remote)

            for temp_file in (local, base, remote):
                if os.name == "nt":
                    os.chmod(temp_file, stat.S_IWRITE)
                os.remove(temp_file)

            return filename, is_temp

        path = path[len(self.root) + 1:]
        if os.name == "nt":
            path = path.replace("\\", "/")

        args = ["git", "show", ":%s:%s" % (self.conflict_map[conflict], path)]
        process = subprocess.Popen(args,
                                   cwd=self.location, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        vc_file = process.stdout

        # Error handling here involves doing nothing; in most cases, the only
        # sane response is to return an empty temp file.

        prefix = 'meld-tmp-%s-' % _vc.conflicts[conflict]
        with tempfile.NamedTemporaryFile(prefix=prefix, delete=False) as f:
            shutil.copyfileobj(vc_file, f)
        return f.name, True

    def get_path_for_repo_file(self, path, commit=None):
        if commit is None:
            commit = "HEAD"
        else:
            raise NotImplementedError()

        if not path.startswith(self.root + os.path.sep):
            raise _vc.InvalidVCPath(self, path, "Path not in repository")
        path = path[len(self.root) + 1:]
        if os.name == "nt":
            path = path.replace("\\", "/")

        obj = commit + ":" + path
        process = subprocess.Popen([self.CMD, "cat-file", "blob", obj],
                                   cwd=self.root, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        vc_file = process.stdout

        # Error handling here involves doing nothing; in most cases, the only
        # sane response is to return an empty temp file.

        with tempfile.NamedTemporaryFile(prefix='meld-tmp', delete=False) as f:
            shutil.copyfileobj(vc_file, f)
        return f.name

    @classmethod
    def valid_repo(cls, path):
        # TODO: On Windows, this exit code is wrong under the normal shell; it
        # appears to be correct under the default git bash shell however.
        return not _vc.call([cls.CMD, "branch"], cwd=path)

    def _get_modified_files(self, path):
        # Update the index to avoid reading stale status information
        proc = self.run("update-index", "--refresh")

        # Get status differences between the index and the repo HEAD
        proc = self.run("diff-index", "--cached", "HEAD", "--relative", path)
        entries = proc.stdout.read().split("\n")[:-1]

        # Get status differences between the index and files-on-disk
        proc = self.run("diff-files", "-0", "--relative", path)
        entries += proc.stdout.read().split("\n")[:-1]

        # Files can show up in both lists, e.g., if a file is modified,
        # added to the index and changed again, so we uniquify.
        # TODO: This doesn't work as expected for many cases; we should
        # pick the last entry (diff to disk) based on filename.
        return list(set(entries))

    def _update_tree_state_cache(self, path):
        """ Update the state of the file(s) at self._tree_cache['path'] """
        while 1:
            try:
                entries = self._get_modified_files(path)

                # Identify ignored files and folders
                proc = self.run(
                    "ls-files", "--others", "--ignored", "--exclude-standard",
                    "--directory", path)
                ignored_entries = proc.stdout.read().split("\n")[:-1]

                # Identify unversioned files
                proc = self.run(
                    "ls-files", "--others", "--exclude-standard", path)
                unversioned_entries = proc.stdout.read().split("\n")[:-1]

                break
            except OSError as e:
                if e.errno != errno.EAGAIN:
                    raise

        def get_real_path(name):
            name = name.strip()
            if os.name == 'nt':
                # Git returns unix-style paths on Windows
                name = os.path.normpath(name)

            # Unicode file names and file names containing quotes are
            # returned by git as quoted strings
            if name[0] == '"':
                name = name[1:-1].decode('string_escape')
            return os.path.abspath(
                os.path.join(self.location, name))

        if len(entries) == 0 and os.path.isfile(path):
            # If we're just updating a single file there's a chance that it
            # was it was previously modified, and now has been edited so that
            # it is un-modified.  This will result in an empty 'entries' list,
            # and self._tree_cache['path'] will still contain stale data.
            # When this corner case occurs we force self._tree_cache['path']
            # to STATE_NORMAL.
            self._tree_cache[get_real_path(path)] = _vc.STATE_NORMAL
        else:
            tree_meta_cache = defaultdict(list)
            staged = set()
            unstaged = set()

            for entry in entries:
                columns = self.DIFF_RE.search(entry).groups()
                old_mode, new_mode, old_sha, new_sha, statekey, path = columns
                state = self.state_map.get(statekey.strip(), _vc.STATE_NONE)
                path = get_real_path(path)
                self._tree_cache[path] = state
                # Git entries can't be MISSING; that's just an unstaged REMOVED
                self._add_missing_cache_entry(path, state)
                if old_mode != new_mode:
                    msg = _("Mode changed from %s to %s" %
                            (old_mode, new_mode))
                    tree_meta_cache[path].append(msg)
                collection = unstaged if new_sha == NULL_SHA else staged
                collection.add(path)

            for path in staged:
                tree_meta_cache[path].append(
                    _("Partially staged") if path in unstaged else _("Staged"))

            for path, msgs in tree_meta_cache.items():
                self._tree_meta_cache[path] = "; ".join(msgs)

            for path in ignored_entries:
                self._tree_cache[get_real_path(path)] = _vc.STATE_IGNORED

            for path in unversioned_entries:
                self._tree_cache[get_real_path(path)] = _vc.STATE_NONE
