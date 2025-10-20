#!/usr/bin/env python2.7
"""
Simple VisTrails .vt File Reader

This is a truly minimal reader that parses .vt files directly using XML,
without requiring VisTrails to be fully initialized.

Dependencies: Python 2.7 + XML (built-in)
"""

from __future__ import print_function
import sys
import os
import xml.etree.ElementTree as ET
import zipfile


def load_vt_xml(filename):
    """Load a .vt file and return the XML tree.

    .vt files are actually ZIP archives containing an XML file.
    """
    # Check if it's a ZIP file
    if zipfile.is_zipfile(filename):
        with zipfile.ZipFile(filename, 'r') as zf:
            # The main vistrail XML is usually in 'vistrail' or 'vistrail.xml'
            if 'vistrail' in zf.namelist():
                xml_content = zf.read('vistrail')
            elif 'vistrail.xml' in zf.namelist():
                xml_content = zf.read('vistrail.xml')
            else:
                # Try the first XML file
                for name in zf.namelist():
                    if name.endswith('.xml'):
                        xml_content = zf.read(name)
                        break
                else:
                    raise Exception("No XML file found in .vt archive")

            root = ET.fromstring(xml_content)
            return root
    else:
        # Try to parse as plain XML
        tree = ET.parse(filename)
        root = tree.getroot()
        return root


def print_vistrail_info(root):
    """Print basic information from the XML."""
    print("=" * 60)
    print("VisTrails File Information")
    print("=" * 60)

    # Count actions (versions)
    actions = root.findall('.//action')
    print("\nTotal versions: {}".format(len(actions)))

    # Find tagged versions
    tags = {}
    for tag in root.findall('.//tag'):
        name = tag.get('name')
        value = tag.get('value')
        if name and value:
            tags[name] = value

    if tags:
        print("\nTagged versions ({}):".format(len(tags)))
        for name, version in sorted(tags.items()):
            print("  - {}: version {}".format(name, version))

    # Get latest version (highest action id)
    max_version = 0
    for action in actions:
        version_id = int(action.get('id', 0))
        if version_id > max_version:
            max_version = version_id

    print("\nLatest version: {}".format(max_version))
    return max_version


def print_workflow_info(root, version_id=None):
    """Print workflow information from XML."""
    print("\n" + "=" * 60)
    print("Workflow Information")
    print("=" * 60)

    # Find modules
    modules = root.findall('.//module')
    print("\nModules ({}):".format(len(modules)))

    module_dict = {}
    for module in modules:
        mod_id = module.get('id')
        name = module.get('name', 'Unknown')
        package = module.get('package', 'Unknown')
        namespace = module.get('namespace', '')

        module_dict[mod_id] = {
            'name': name,
            'package': package,
            'namespace': namespace
        }

        print("  - {} ({}::{})".format(name, package, namespace))
        print("    ID: {}".format(mod_id))

        # Find functions (parameters)
        functions = module.findall('.//function')
        if functions:
            print("    Parameters:")
            for func in functions:
                func_name = func.get('name', 'Unknown')
                # Find parameter values
                params = []
                for param in func.findall('.//parameter'):
                    val = param.get('val', '')
                    if not val:
                        # Try to find value in nested elements
                        val_elem = param.find('value')
                        if val_elem is not None and val_elem.text:
                            val = val_elem.text
                    params.append(val)

                if params:
                    print("      {} = {}".format(func_name, ", ".join(params)))

    # Find connections
    connections = root.findall('.//connection')
    print("\nConnections ({}):".format(len(connections)))

    for conn in connections:
        # Get source and destination ports
        source = conn.find('port[@type="source"]')
        dest = conn.find('port[@type="destination"]')

        if source is not None and dest is not None:
            src_module_id = source.get('moduleId')
            src_port = source.get('name', 'output')
            dst_module_id = dest.get('moduleId')
            dst_port = dest.get('name', 'input')

            src_name = module_dict.get(src_module_id, {}).get('name', 'Module' + src_module_id)
            dst_name = module_dict.get(dst_module_id, {}).get('name', 'Module' + dst_module_id)

            print("  - {}:{} -> {}:{}".format(src_name, src_port, dst_name, dst_port))


def export_workflow_text(root, output_file=None):
    """Export workflow to a text file."""
    lines = []
    lines.append("# VisTrails Workflow Export")
    lines.append("")

    # Modules
    modules = root.findall('.//module')
    lines.append("## Modules ({})".format(len(modules)))

    for module in modules:
        mod_id = module.get('id')
        name = module.get('name', 'Unknown')
        package = module.get('package', 'Unknown')
        lines.append("{}: {} ({})".format(mod_id, name, package))

    lines.append("")

    # Connections
    connections = root.findall('.//connection')
    lines.append("## Connections ({})".format(len(connections)))

    for conn in connections:
        source = conn.find('port[@type="source"]')
        dest = conn.find('port[@type="destination"]')

        if source is not None and dest is not None:
            src_id = source.get('moduleId')
            dst_id = dest.get('moduleId')
            lines.append("Module {} -> Module {}".format(src_id, dst_id))

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
        print("Usage: python simple_vt_reader.py <file.vt> [options]")
        print("\nOptions:")
        print("  --export FILE       Export workflow to text file")
        print("\nExamples:")
        print("  python simple_vt_reader.py workflow.vt")
        print("  python simple_vt_reader.py workflow.vt --export output.txt")
        sys.exit(1)

    filename = sys.argv[1]

    if not os.path.exists(filename):
        print("Error: File not found: {}".format(filename))
        sys.exit(1)

    print("Loading {}...".format(filename))

    try:
        root = load_vt_xml(filename)

        if '--export' in sys.argv:
            idx = sys.argv.index('--export')
            output_file = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else None
            export_workflow_text(root, output_file)
        else:
            # Default: print info and workflow
            print_vistrail_info(root)
            print_workflow_info(root)

    except ET.ParseError as e:
        print("Error parsing XML: {}".format(e))
        sys.exit(1)
    except Exception as e:
        print("Error: {}".format(e))
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
