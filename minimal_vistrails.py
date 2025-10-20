#!/usr/bin/env python2.7
"""
Minimal VisTrails: Load and inspect .vt files

This demonstrates the minimal components needed to:
1. Load a .vt file
2. Inspect its contents (versions, workflows, modules)
3. Print workflow information

Dependencies (minimal):
- Python 2.7
- XML parsing (built-in)
- No GUI (PyQt4) required
- No VTK required
"""

from __future__ import print_function
import sys
import os

# Add VisTrails to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Initialize VisTrails minimal configuration
from vistrails.core.configuration import get_vistrails_configuration

from vistrails.core.db.locator import XMLFileLocator
from vistrails.core.db.io import load_vistrail
from vistrails.core.vistrail.vistrail import Vistrail


def load_vt_file(filename):
    """Load a .vt file and return the vistrail object."""
    locator = XMLFileLocator(filename)
    (vistrail, abstractions, thumbnails, mashups) = load_vistrail(locator)
    return vistrail


def print_vistrail_info(vistrail):
    """Print basic information about a vistrail."""
    print("=" * 60)
    print("VisTrails File Information")
    print("=" * 60)

    # Version tree info
    versions = vistrail.get_version_graph()
    print("\nTotal versions: {}".format(len(versions)))

    # List all tagged versions
    tags = vistrail.get_tagMap()
    if tags:
        print("\nTagged versions ({}):".format(len(tags)))
        for tag, version_id in sorted(tags.items()):
            print("  - {}: version {}".format(tag, version_id))

    # Get latest version
    latest = vistrail.get_latest_version()
    print("\nLatest version: {}".format(latest))

    return latest


def print_workflow_info(vistrail, version_id):
    """Print information about a specific workflow version."""
    print("\n" + "=" * 60)
    print("Workflow Version {}".format(version_id))
    print("=" * 60)

    # Get the pipeline (workflow) for this version
    pipeline = vistrail.getPipeline(version_id)

    # Module information
    modules = pipeline.module_list
    print("\nModules ({}):".format(len(modules)))
    for module in modules:
        print("  - {} ({}::{})".format(module.name, module.package, module.namespace))
        print("    ID: {}".format(module.id))

        # Print functions (parameters)
        if module.functions:
            print("    Parameters:")
            for func in module.functions:
                params = ", ".join(p.value for p in func.params)
                print("      {} = {}".format(func.name, params))

    # Connection information
    connections = pipeline.connection_list
    print("\nConnections ({}):".format(len(connections)))
    for conn in connections:
        src_module = pipeline.modules[conn.source.moduleId]
        dst_module = pipeline.modules[conn.destination.moduleId]
        print("  - {}:{} -> {}:{}".format(src_module.name, conn.source.name,
                                          dst_module.name, conn.destination.name))


def print_workflow_tree(vistrail):
    """Print the version tree structure."""
    print("\n" + "=" * 60)
    print("Version Tree")
    print("=" * 60)

    # Get all versions
    versions = vistrail.actionMap.keys()
    tags = vistrail.get_tagMap()

    # Print tree (simplified)
    for version in sorted(versions):
        action = vistrail.actionMap.get(version)
        if action:
            parent = action.prevId
            tag = [t for t, v in tags.items() if v == version]
            tag_str = " [{}]".format(tag[0]) if tag else ""
            print("  Version {}{} (parent: {})".format(version, tag_str, parent))
            if action.operations:
                print("    Operations: {}".format(len(action.operations)))


def export_workflow_text(vistrail, version_id, output_file=None):
    """Export workflow to a text representation."""
    pipeline = vistrail.getPipeline(version_id)

    lines = []
    lines.append("# Workflow Version {}".format(version_id))
    lines.append("# Modules: {}".format(len(pipeline.module_list)))
    lines.append("# Connections: {}".format(len(pipeline.connection_list)))
    lines.append("")

    lines.append("## Modules")
    for module in pipeline.module_list:
        lines.append("{}: {} ({})".format(module.id, module.name, module.package))
        for func in module.functions:
            params = ", ".join(p.value for p in func.params)
            lines.append("  {} = {}".format(func.name, params))
        lines.append("")

    lines.append("## Connections")
    for conn in pipeline.connection_list:
        src_module = pipeline.modules[conn.source.moduleId]
        dst_module = pipeline.modules[conn.destination.moduleId]
        lines.append("{}:{} -> {}:{}".format(src_module.name, conn.source.name,
                                             dst_module.name, conn.destination.name))

    text = "\n".join(lines)

    if output_file:
        with open(output_file, 'w') as f:
            f.write(text)
        print("\nWorkflow exported to {}".format(output_file))
    else:
        print("\n" + text)

    return text


def main():
    if len(sys.argv) < 2:
        print("Usage: python minimal_vistrails.py <file.vt> [options]")
        print("\nOptions:")
        print("  --info              Print vistrail information (default)")
        print("  --workflow VERSION  Print specific workflow version")
        print("  --tree              Print version tree")
        print("  --export FILE       Export workflow to text file")
        print("\nExamples:")
        print("  python minimal_vistrails.py workflow.vt")
        print("  python minimal_vistrails.py workflow.vt --workflow 5")
        print("  python minimal_vistrails.py workflow.vt --export output.txt")
        sys.exit(1)

    filename = sys.argv[1]

    if not os.path.exists(filename):
        print("Error: File not found: {}".format(filename))
        sys.exit(1)

    print("Loading {}...".format(filename))
    vistrail = load_vt_file(filename)

    # Parse command line options
    if '--tree' in sys.argv:
        print_workflow_tree(vistrail)
    elif '--workflow' in sys.argv:
        idx = sys.argv.index('--workflow')
        if idx + 1 < len(sys.argv):
            version_id = int(sys.argv[idx + 1])
            print_workflow_info(vistrail, version_id)
        else:
            print("Error: --workflow requires a version number")
    elif '--export' in sys.argv:
        idx = sys.argv.index('--export')
        output_file = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else None
        latest = vistrail.get_latest_version()
        export_workflow_text(vistrail, latest, output_file)
    else:
        # Default: print info and latest workflow
        latest = print_vistrail_info(vistrail)
        print_workflow_info(vistrail, latest)


if __name__ == '__main__':
    main()
