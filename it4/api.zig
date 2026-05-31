pub const author_ir = @import("author_ir.zig");
pub const build_ir = @import("build_ir.zig");
pub const core_ir = @import("core_ir.zig");
pub const lower = @import("lower.zig");
pub const traverse = @import("traverse.zig");
pub const validate = @import("validate.zig");
pub const emit_html = @import("emit_html.zig");
pub const hash = @import("hash.zig");
pub const serialize_mod = @import("serialize.zig");
pub const privacy = @import("privacy.zig");
pub const transform = @import("transform.zig");
pub const adapter = @import("adapter.zig");
pub const parser = @import("parser.zig");

pub const build = struct {
    pub const Builder = build_ir.Builder;
    pub const MetadataSpec = build_ir.MetadataSpec;
    pub const AuthorDocument = author_ir.Document;
    pub const ParsedDocument = adapter.ParsedDocument;
    pub const Event = adapter.Event;
};

pub const core = struct {
    pub const Document = core_ir.Document;
    pub const Diagnostic = core_ir.Diagnostic;
    pub const DiagnosticLevel = core_ir.DiagnosticLevel;
    pub const DiagnosticSubject = core_ir.DiagnosticSubject;
    pub const Walker = traverse.Walker;
};

pub const lower_doc = lower.lower;

pub const validate_doc = struct {
    pub const document = validate.validate;
    pub const serialized = serialize_mod.validate;
};

pub const emit = struct {
    pub const html = emit_html.emitHtml;
};

pub const hash_doc = hash.hashDocument;

pub const binary = struct {
    pub const serialize = serialize_mod.serialize;
    pub const deserialize = serialize_mod.deserialize;
    pub const validate = serialize_mod.validate;
};

pub const privacy_scan = struct {
    pub const scan = privacy.scanDocument;
    pub const applyPolicy = privacy.applyPolicy;
};

pub const rewrite = struct {
    pub const clone = transform.cloneDocument;
    pub const renameIdentifier = transform.renameIdentifier;
    pub const retitleSection = transform.retitleSection;
    pub const replaceText = transform.replaceText;
    pub const updateLinkTarget = transform.updateLinkTarget;
    pub const retargetReference = transform.retargetReference;
    pub const addRootSection = transform.addRootSection;
    pub const insertRootSectionAt = transform.insertRootSectionAt;
    pub const removeRootSectionById = transform.removeRootSectionById;
    pub const reorderRoots = transform.reorderRoots;
    pub const removeSectionById = transform.removeSectionById;
    pub const appendChildSection = transform.appendChildSection;
    pub const insertChildSectionAt = transform.insertChildSectionAt;
};

pub const ingest = struct {
    pub const toAuthorDocument = adapter.toAuthorDocument;
    pub const lowerParsedDocument = adapter.lowerParsedDocument;
    pub const lowerEventStream = adapter.lowerEventStream;
    pub const parseMiniMarkdown = parser.parseMiniMarkdown;
};

pub const Builder = build.Builder;
pub const MetadataSpec = build.MetadataSpec;
pub const AuthorDocument = build.AuthorDocument;
pub const ParsedDocument = build.ParsedDocument;
pub const Event = build.Event;
pub const CoreDocument = core.Document;
pub const Diagnostic = core.Diagnostic;
pub const DiagnosticLevel = core.DiagnosticLevel;
pub const DiagnosticSubject = core.DiagnosticSubject;
pub const Walker = core.Walker;
pub const lowerDocument = lower_doc;
pub const validateDocument = validate_doc.document;
pub const emitHtml = emit.html;
pub const hashDocument = hash_doc;
pub const serializeDocument = binary.serialize;
pub const deserializeDocument = binary.deserialize;
pub const validateSerialized = binary.validate;
pub const scanDocumentPrivacy = privacy_scan.scan;
pub const applyPrivacyPolicy = privacy_scan.applyPolicy;
pub const cloneCoreDocument = rewrite.clone;
pub const renameCoreIdentifier = rewrite.renameIdentifier;
pub const retitleCoreSection = rewrite.retitleSection;
pub const replaceCoreText = rewrite.replaceText;
pub const updateCoreLinkTarget = rewrite.updateLinkTarget;
pub const retargetCoreReference = rewrite.retargetReference;
pub const removeCoreSectionById = rewrite.removeSectionById;
pub const appendCoreChildSection = rewrite.appendChildSection;
pub const insertRootCoreSectionAt = rewrite.insertRootSectionAt;
pub const insertCoreChildSectionAt = rewrite.insertChildSectionAt;
pub const lowerParsedDocument = ingest.lowerParsedDocument;
pub const lowerEventStream = ingest.lowerEventStream;
pub const parseMiniMarkdown = ingest.parseMiniMarkdown;
