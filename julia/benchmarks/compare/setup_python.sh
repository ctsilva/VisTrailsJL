#!/bin/sh
# Python side of the Julia/Python comparison: a fixed tree of ProgressiVis
# (git archive of a commit of progressivis-parallel, run from PYTHONPATH, as
# in the paper's protocol) and two interpreters, CPython 3.14 standard and
# free-threaded, with its dependencies.
#
#   PROGRESSIVIS=~/src/progressivis-parallel COMMIT=HEAD ./setup_python.sh
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
PV=${PROGRESSIVIS:-$HOME/src/progressivis-parallel}
COMMIT=${COMMIT:-HEAD}
SHA=$(git -C "$PV" rev-parse --short "$COMMIT")
TREE=$HERE/trees/$SHA
if [ ! -d "$TREE" ]; then
  mkdir -p "$TREE"
  git -C "$PV" archive "$SHA" | tar -x -C "$TREE"
  printf '__version__ = version = "0+%s"\n__version_tuple__ = version_tuple = (0, "%s")\n' "$SHA" "$SHA" \
    > "$TREE/progressivis/_version.py"
fi
ln -sfn "$TREE" "$HERE/trees/head"
DEPS="numpy scipy numexpr pandas pyarrow scikit-learn threadpoolctl pyyaml pyroaring python-dateutil
      requests typeguard multipledispatch datasketches Pillow s3fs"
for v in std ft; do
  py=$([ $v = ft ] && echo 3.14t || echo 3.14)
  [ -x "$HERE/.venv-$v/bin/python" ] || uv venv -q --python "$py" "$HERE/.venv-$v"
  uv pip install -q --python "$HERE/.venv-$v/bin/python" $DEPS
done
echo "tree: $TREE ($SHA)"
