# [<](README.md) &nbsp; Documentation Conventions

## Rebuilding the content table

Actions which requires the main content table to be updated:

1. Adding a file
1. Moving a file
1. Deleting a file
1. Updating a file's main header

To update the content table:

1. You would need to install the dependencies by running:

    ```sh
    yarn
    ```

2. To rebuild, just run:

    ```sh
    yarn generate-toc
    ```

## Adding a document

When adding a  document file for this repo it should follow this structure:

```markdown

# [<](README.md) &nbsp; ${main_header}

${table_of_content}

&nbsp;

${content}

[Back to the top](#--${main_header_lowercased_dashed})

```

- main_header - The main title name for the page.\
For example for this page it's: "Documentation Conventions")

- main_header_lowercased_dashed - the same as the "main_header" only all lower caps and separated by dashes instead of spaces.\
For example for this page it's: "documentation-conventions")

- table_of_content (Optional) - If needed (page is long) add table of content for the page.

- content - The actual content of the page which should only use "native" markdown syntax, without any html tags.

[Back to the top](#--documentation-conventions)
