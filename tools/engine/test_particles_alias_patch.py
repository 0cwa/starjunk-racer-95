import tempfile
import unittest
from pathlib import Path

from apply_starjunk_port_patches import apply_particles_alias_patch


class ParticleAliasPatchTests(unittest.TestCase):
    def test_emission_fallbacks_are_distinct_and_both_are_cleaned_up(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            source = Path(temporary_directory)
            storage = source / "servers/rendering/renderer_rd/storage_rd"
            storage.mkdir(parents=True)
            header = storage / "particles_storage.h"
            implementation = storage / "particles_storage.cpp"
            header.write_text(
                "\t\tRID unused_emission_storage_buffer;\n"
                "\t\tRID unused_trail_storage_buffer;\n",
                encoding="utf-8",
            )
            implementation.write_text(
                "\tif (particles->unused_emission_storage_buffer.is_valid()) {\n"
                "\t\tRD::get_singleton()->free_rid(particles->unused_emission_storage_buffer);\n"
                "\t\tparticles->unused_emission_storage_buffer = RID();\n"
                "\t}\n\n"
                "\tif (particles->unused_trail_storage_buffer.is_valid()) {\n"
                "\t\tRD::get_singleton()->free_rid(particles->unused_trail_storage_buffer);\n"
                "\t}\n"
                "\t\tu.binding = 2;\n"
                "\t\t\t\t_particles_ensure_unused_emission_buffer(p_particles);\n"
                "\t\t\t\tu.append_id(p_particles->unused_emission_storage_buffer);\n"
                "\t\t\tuniforms.push_back(u);\n"
                "\t\t\tu.binding = 3;\n"
                "\t\t\t} else {\n"
                "\t\t\t\t_particles_ensure_unused_emission_buffer(p_particles);\n"
                "\t\t\t\tu.append_id(p_particles->unused_emission_storage_buffer);\n"
                "\t\t\t}\n"
                "\t\t\tuniforms.push_back(u);\n"
                "\t\t}\n\n"
                "\t\tp_particles->particles_material_uniform_set = "
                "RD::get_singleton()->uniform_set_create(uniforms, "
                "particles_shader.default_shader_rd, 1);\n",
                encoding="utf-8",
            )

            apply_particles_alias_patch(source)

            patched_header = header.read_text(encoding="utf-8")
            patched_implementation = implementation.read_text(encoding="utf-8")
            self.assertIn("RID unused_sub_emission_storage_buffer;", patched_header)
            self.assertIn(
                "u.binding = 2;\n"
                "\t\t\t\t_particles_ensure_unused_emission_buffer(p_particles);\n"
                "\t\t\t\tu.append_id(p_particles->unused_emission_storage_buffer);",
                patched_implementation,
            )
            self.assertIn(
                "u.binding = 3;\n"
                "\t\t\t} else {\n"
                "\t\t\t\t// SourceEmission and DestEmission are both writable storage bindings.",
                patched_implementation,
            )
            self.assertIn(
                "u.append_id(p_particles->unused_sub_emission_storage_buffer);",
                patched_implementation,
            )
            self.assertIn(
                "free_rid(particles->unused_sub_emission_storage_buffer);",
                patched_implementation,
            )
            self.assertIn(
                "particles->unused_sub_emission_storage_buffer = RID();",
                patched_implementation,
            )


if __name__ == "__main__":
    unittest.main()
