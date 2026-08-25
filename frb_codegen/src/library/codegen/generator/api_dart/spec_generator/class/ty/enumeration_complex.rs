use crate::codegen::generator::api_dart::spec_generator::class::field::{
    generate_field_default, generate_field_required_modifier,
};
use crate::codegen::generator::api_dart::spec_generator::class::ApiDartGeneratedClass;
use crate::codegen::generator::api_dart::spec_generator::misc::{
    generate_dart_comments, generate_dart_maybe_implements_exception, generate_dart_metadata,
};
use crate::codegen::ir::mir::field::MirField;
use crate::codegen::ir::mir::ty::enumeration::{MirEnum, MirEnumVariant, MirVariantKind};
use crate::codegen::ir::mir::ty::structure::MirStruct;
use crate::library::codegen::generator::api_dart::spec_generator::base::*;
use crate::library::codegen::generator::api_dart::spec_generator::info::ApiDartGeneratorInfoTrait;
use crate::utils::basic_code::dart_header_code::DartHeaderCode;
use itertools::Itertools;

const BACKTRACE_IDENT: &str = "backtrace";

impl EnumRefApiDartGenerator<'_> {
    pub(crate) fn generate_mode_complex(
        &self,
        src: &MirEnum,
        extra_body: &str,
        header: DartHeaderCode,
    ) -> Option<ApiDartGeneratedClass> {
        let variants = src
            .variants()
            .iter()
            .map(|variant| self.generate_mode_complex_variant(variant, src.is_non_final))
            .collect_vec()
            .join("\n");
        let name = &self.mir.ident.0.name;
        let sealed = if self.context.config.dart3 {
            "sealed"
        } else {
            ""
        };
        let maybe_implements_exception =
            generate_dart_maybe_implements_exception(self.mir.is_exception);

        let json_serializable_extra_code =
            compute_json_serializable_extra_code(src.needs_json_serializable, name);

        // `#[frb(non_final)]` (or the legacy `flutter_rust_bridge:mutable` doc directive) opts
        // the generated freezed union into `@unfreezed`, giving mutable fields instead of the
        // default immutable `@freezed` ones.
        let freezed_annotation = if src.is_non_final {
            "@unfreezed"
        } else {
            "@freezed"
        };

        Some(ApiDartGeneratedClass {
            namespace: src.name.namespace.clone(),
            class_name: name.clone(),
            code: format!(
                "{freezed_annotation}
                {sealed} class {name} with _${name} {maybe_implements_exception} {{
                    const {name}._();

                    {variants}

                    {json_serializable_extra_code}

                    {extra_body}
                }}",
            ),
            needs_freezed: true,
            needs_json_serializable: src.needs_json_serializable,
            header,
        })
    }

    fn generate_mode_complex_variant(&self, variant: &MirEnumVariant, is_non_final: bool) -> String {
        let (args, metadata) = match &variant.kind {
            MirVariantKind::Value => ("".to_owned(), "".to_owned()),
            MirVariantKind::Struct(st) => {
                let args = if st.is_fields_named {
                    self.generate_variant_struct_named(st)
                } else {
                    self.generate_variant_struct_unnamed(st)
                };
                (args, generate_dart_metadata(&st.dart_metadata_raw))
            }
        };

        let implements_exception = self.generate_implements_exception(variant);

        // `@unfreezed` classes have mutable fields, so their factory constructors cannot be
        // `const` (mirrors freezed's own requirement).
        let maybe_const = if is_non_final { "" } else { "const" };

        format!(
            "{} {}{metadata}{maybe_const} factory {}.{}({}) = {};",
            implements_exception,
            generate_dart_comments(&variant.comments),
            self.mir.ident.0.name,
            variant.name.dart_style(),
            args,
            variant.wrapper_name.rust_style(true),
        )
    }

    fn generate_variant_struct_unnamed(&self, st: &MirStruct) -> String {
        let types = st
            .fields
            .iter()
            .map(|field| {
                // If no split, default values are not valid.
                let default = if optional_boundary_index(&st.fields).is_some() {
                    {
                        generate_field_default(field, true, self.context.config.dart_enums_style)
                    }
                } else {
                    Default::default()
                };
                let comments = generate_dart_comments(&field.comments);
                let type_str =
                    ApiDartGenerator::new(field.ty.clone(), self.context).dart_api_type();
                let name_str = field.name.dart_style();
                format!("{comments} {default} {type_str} {name_str},")
            })
            .collect_vec();

        if let Some(idx) = optional_boundary_index(&st.fields) {
            let before = &types[..idx];
            let after = &types[idx..];
            format!("{}[{}]", before.join(""), after.join(""))
        } else {
            types.join("")
        }
    }

    fn generate_variant_struct_named(&self, st: &MirStruct) -> String {
        let fields = st
            .fields
            .iter()
            .map(|field| {
                format!(
                    "{comments} {default} {required}{} {} ,",
                    ApiDartGenerator::new(field.ty.clone(), self.context).dart_api_type(),
                    field.name.dart_style(),
                    required = generate_field_required_modifier(field),
                    comments = generate_dart_comments(&field.comments),
                    default =
                        generate_field_default(field, true, self.context.config.dart_enums_style),
                )
            })
            .collect_vec();
        format!("{{ {} }}", fields.join(""))
    }

    fn generate_implements_exception(&self, variant: &MirEnumVariant) -> &str {
        let has_backtrace = matches!(&variant.kind,
            MirVariantKind::Struct(MirStruct {is_fields_named: true, fields, ..}) if fields.iter().any(|field| field.name.rust_style(true) == BACKTRACE_IDENT));
        if self.mir.is_exception && has_backtrace {
            "@Implements<FrbBacktracedException>()"
        } else {
            ""
        }
    }
}

fn optional_boundary_index(fields: &[MirField]) -> Option<usize> {
    fields
        .iter()
        .enumerate()
        .find(|(_, field)| field.is_optional())
        .and_then(|(idx, _)| {
            fields[idx..]
                .iter()
                .all(|field| field.is_optional())
                .then_some(idx)
        })
}

pub(crate) fn compute_json_serializable_extra_code(
    needs_json_serializable: bool,
    name: &str,
) -> String {
    if needs_json_serializable {
        format!("factory {name}.fromJson(Map<String, dynamic> json) => _${name}FromJson(json);")
    } else {
        "".to_owned()
    }
}
