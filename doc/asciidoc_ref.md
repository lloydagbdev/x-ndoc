## AsciiDoc Native IR Canvas

### 1. Core document structure

| Element                 | Definition                                                                                                   |
| ----------------------- | ------------------------------------------------------------------------------------------------------------ |
| **Document**            | Root container for the entire AsciiDoc file. Holds document metadata, attributes, and top-level content.     |
| **Section**             | A heading and everything nested under it. Sections form the main hierarchy of the document.                  |
| **Paragraph**           | A block of normal prose text. Usually contains inline elements such as text, links, emphasis, and footnotes. |
| **Block title**         | A title attached to the block that follows it, such as a titled table, example, or image.                    |
| **Attribute entry**     | A document-level or block-level key-value setting.                                                           |
| **Attribute reference** | A placeholder that resolves to an attribute value.                                                           |

---

### 2. Inline elements

| Element                | Definition                                                                   |
| ---------------------- | ---------------------------------------------------------------------------- |
| **Text**               | Plain textual content.                                                       |
| **Strong**             | Bold inline content.                                                         |
| **Emphasis**           | Italic inline content.                                                       |
| **Monospace**          | Inline literal or code-style content.                                        |
| **Mark**               | Highlighted text.                                                            |
| **Superscript**        | Text raised above the baseline.                                              |
| **Subscript**          | Text lowered below the baseline.                                             |
| **Link**               | External URL or link macro.                                                  |
| **Cross-reference**    | Internal reference to another section, anchor, figure, table, or block.      |
| **Anchor**             | Named target that can be referenced elsewhere.                               |
| **Footnote**           | Inline note rendered separately, usually at the bottom of a page or section. |
| **Inline image**       | Image embedded inside a text flow.                                           |
| **Line break**         | Explicit line break inside inline content.                                   |
| **Inline passthrough** | Raw inline content passed directly to the output backend.                    |

---

### 3. List elements

| Element              | Definition                                                                              |
| -------------------- | --------------------------------------------------------------------------------------- |
| **List**             | Container for ordered, unordered, checklist, callout, or description-style items.       |
| **List item**        | One item inside a list. Can contain paragraphs, nested lists, blocks, or other content. |
| **Description list** | A list made of terms and descriptions.                                                  |
| **Description item** | One term and its associated explanation or body content.                                |
| **Callout list**     | List that explains numbered callouts inside source code or listing blocks.              |
| **Checklist item**   | A list item with checked, unchecked, or indeterminate task state.                       |

---

### 4. Block elements

| Element               | Definition                                                                        |
| --------------------- | --------------------------------------------------------------------------------- |
| **Admonition**        | A semantic warning-style block such as Note, Tip, Important, Caution, or Warning. |
| **Listing block**     | Source code or terminal-style block.                                              |
| **Literal block**     | Preformatted literal text.                                                        |
| **Example block**     | A general example container.                                                      |
| **Quote block**       | Quoted text, optionally with attribution or citation.                             |
| **Sidebar block**     | Side content separated from the main flow.                                        |
| **Open block**        | Generic container block that can act as a wrapper for other content.              |
| **Passthrough block** | Raw backend-specific block content.                                               |
| **Image block**       | Standalone image block.                                                           |
| **Include**           | Directive that pulls in content from another file.                                |
| **Comment**           | Non-rendered author/editor note.                                                  |
| **Conditional block** | Content included or excluded depending on document attributes or backend.         |
| **Thematic break**    | Horizontal divider.                                                               |
| **Page break**        | Explicit page break for paged outputs.                                            |

---

### 5. Table elements

| Element          | Definition                                                                            |
| ---------------- | ------------------------------------------------------------------------------------- |
| **Table**        | Container for rows, columns, and cells.                                               |
| **Table column** | Column-level formatting metadata such as width, alignment, or content style.          |
| **Table row**    | One horizontal row of cells.                                                          |
| **Table cell**   | Individual table cell. Can contain raw text, inline content, or nested block content. |
| **Table header** | Header row or cells used to label columns.                                            |
| **Table footer** | Footer row or cells, depending on backend support.                                    |

---

### 6. Media and references

| Element                | Definition                                                     |
| ---------------------- | -------------------------------------------------------------- |
| **Image**              | Inline or block-level image reference.                         |
| **Video**              | Embedded or linked video media, if supported by the processor. |
| **Audio**              | Embedded or linked audio media, if supported by the processor. |
| **Bibliography entry** | Reference entry for citations.                                 |
| **Index term**         | Term inserted into an index.                                   |
| **Glossary term**      | Term and definition used in glossary-like documents.           |

---

### 7. Metadata and processor support

| Element               | Definition                                                                                          |
| --------------------- | --------------------------------------------------------------------------------------------------- |
| **Metadata**          | Shared node information such as ID, title, roles, options, and attributes.                          |
| **Role**              | Semantic or styling class attached to an element.                                                   |
| **Option**            | Behavior modifier such as header, autowidth, interactive checklist, or special substitutions.       |
| **Substitution rule** | Defines how text is transformed: attributes, macros, quotes, replacements, passthroughs, and so on. |
| **Diagnostic**        | Parser or resolver message: warning, error, or informational note.                                  |
| **Custom element**    | Extension point for processor-specific or unknown nodes.                                            |

---

## Hierarchy examples

### Example 1: Basic article hierarchy

```text
Document
└── Section: Introduction
    ├── Paragraph
    │   ├── Text
    │   ├── Emphasis
    │   └── Link
    └── Section: Background
        └── Paragraph
            ├── Text
            └── Cross-reference
```

Meaning: a document contains a section, which contains a paragraph and a nested subsection. Paragraphs contain inline elements.

---

### Example 2: Section with an admonition

```text
Document
└── Section: Installation
    ├── Paragraph
    │   └── Text
    └── Admonition: Warning
        └── Paragraph
            ├── Text
            └── Strong
```

Meaning: admonitions are block-level elements. Their body can contain normal block content, usually paragraphs, lists, or nested blocks.

---

### Example 3: List with nested content

```text
Document
└── Section: Setup Steps
    └── List: Ordered
        ├── List item
        │   └── Paragraph
        │       └── Text
        ├── List item
        │   ├── Paragraph
        │   │   └── Text
        │   └── List: Unordered
        │       ├── List item
        │       │   └── Paragraph
        │       └── List item
        │           └── Paragraph
        └── List item
            └── Paragraph
                ├── Text
                └── Inline image
```

Meaning: list items should be treated as containers, not just plain strings. They can hold paragraphs, nested lists, images, admonitions, and other blocks.

---

### Example 4: Table hierarchy

```text
Document
└── Section: API Summary
    └── Table
        ├── Table column
        ├── Table column
        ├── Table row: Header
        │   ├── Table cell
        │   │   └── Text
        │   └── Table cell
        │       └── Text
        └── Table row
            ├── Table cell
            │   └── Paragraph
            └── Table cell
                └── List
                    ├── List item
                    └── List item
```

Meaning: table cells can contain more than plain text. In AsciiDoc, cells may contain paragraphs, lists, source blocks, or nested AsciiDoc content depending on cell style.

---

### Example 5: Source block with callouts

```text
Document
└── Section: Example
    ├── Listing block
    │   ├── Source text
    │   └── Callout markers
    └── Callout list
        ├── Callout item
        │   └── Paragraph
        └── Callout item
            └── Paragraph
```

Meaning: callouts connect annotations in source code to explanatory list items. The IR should preserve that relationship.

---

### Example 6: Image with title and metadata

```text
Document
└── Section: Architecture
    └── Image block
        ├── Block title
        ├── Target
        ├── Alt text
        ├── Attributes
        └── Anchor
```

Meaning: images often need structured metadata: target path, alt text, title, ID, roles, dimensions, and output options.

---

### Example 7: Quote block

```text
Document
└── Section: Motivation
    └── Quote block
        ├── Attribution
        ├── Citation
        └── Paragraph
            ├── Text
            └── Emphasis
```

Meaning: quote blocks should keep attribution and citation separate from the quoted body.

---

### Example 8: Include and resolved content

Before resolution:

```text
Document
├── Section: Main
└── Include
    ├── Target: chapter-one.adoc
    └── Attributes
```

After resolution:

```text
Document
├── Section: Main
└── Section: Chapter One
    ├── Paragraph
    └── List
```

Meaning: the parser may first create an Include node, then the semantic resolver may replace or expand it into real document content.

---

## Recommended IR layers

### Parse IR

Captures what the source literally contains.

```text
Parse IR
├── Raw lines
├── Delimiters
├── Block titles
├── Attribute entries
├── Include directives
├── Conditional directives
├── Comments
└── Unresolved inline macros
```

### Semantic IR

Captures what the document means after resolution.

```text
Semantic IR
├── Document
├── Sections
├── Paragraphs
├── Lists
├── Tables
├── Blocks
├── Inline formatting
├── Links and references
├── Resolved attributes
├── Anchors
└── Diagnostics
```

### Render IR

Captures what the output backend needs.

```text
Render IR
├── Heading levels
├── Rendered block tree
├── Resolved links
├── Resolved images
├── Numbered sections
├── Table layout
├── Footnote placement
├── Backend-specific passthroughs
└── Final diagnostics
```

---

## Practical rule of thumb

Model AsciiDoc as a **document tree with block nodes and inline nodes**.

```text
Document
└── Blocks
    └── Inline content where needed
```

The most important distinction is:

| Category            | Examples                                                 | Purpose                                   |
| ------------------- | -------------------------------------------------------- | ----------------------------------------- |
| **Block nodes**     | section, paragraph, list, table, image block, admonition | Define document structure                 |
| **Inline nodes**    | text, strong, emphasis, link, footnote                   | Define content inside text flow           |
| **Metadata nodes**  | title, ID, roles, attributes, options                    | Modify or identify another element        |
| **Processor nodes** | include, conditional, passthrough, diagnostic            | Control parsing, resolution, or rendering |
