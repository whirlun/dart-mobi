#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mobi.h>

static void print_index(MOBIIndx *index, const char *name) {
    if (!index) return;
    printf("%s Index:\n", name);
    printf("  Entries: %zu\n", index->entries_count);
}

static void print_parts(MOBIPart *part, const char *name) {
    if (!part) return;
    printf("%s Parts:\n", name);
    int count = 0;
    while (part) {
        printf("  Part %d:\n", count++);
        printf("    Size: %zu\n", part->size);
        printf("    Type: %d\n", part->type);
        part = part->next;
    }
}

static void print_content(MOBIRawml *rawml) {
    if (!rawml || !rawml->markup) return;
    printf("\nRAWML Content:\n");
    printf("=============\n");
    MOBIPart *curr = rawml->markup;
    while (curr) {
        if (curr->data) {
            printf("%.*s\n", (int)curr->size, (char *)curr->data);
        }
        curr = curr->next;
    }
}

void print_rawml_structure(MOBIRawml *rawml) {
    if (!rawml) {
        printf("RAWML is NULL\n");
        return;
    }

    printf("MOBI RAWML Structure:\n");
    printf("==================\n\n");

    // Print indices
    print_index(rawml->guide, "Guide");
    print_index(rawml->ncx, "NCX");
    print_index(rawml->orth, "Orthographic");
    print_index(rawml->infl, "Inflection");

    // Print parts
    print_parts(rawml->flow, "Flow");
    print_parts(rawml->markup, "Markup");
    print_parts(rawml->resources, "Resources");
}

int main(int argc, char *argv[]) {
    /* Initialize main MOBIData structure */
/* Must be deallocated with mobi_free() when not needed */
MOBIData *m = mobi_init();
if (m == NULL) { 
  return -1; 
}

/* Open file for reading */
FILE *file = fopen("./980.mobi", "rb");
if (file == NULL) {
  printf("Failed to open file\n");
  mobi_free(m);
  return -1;
}

/* Load file into MOBIData structure */
/* This structure will hold raw data/metadata from mobi document */
MOBI_RET mobi_ret = mobi_load_file(m, file);
fclose(file);
if (mobi_ret != MOBI_SUCCESS) { 
  printf("Failed to load file\n Error code: %d\n", mobi_ret);
  mobi_free(m);
  return -1;
}

printf("Encryption Type: %d\n", m->rh->encryption_type);
/* Initialize MOBIRawml structure */
/* Must be deallocated with mobi_free_rawml() when not needed */
/* In the next step this structure will be filled with parsed data */
MOBIRawml *rawml = mobi_init_rawml(m);
if (rawml == NULL) {
  printf("Failed to initialize rawml\n Error code: %d\n", mobi_ret);
  mobi_free(m);
  return -1;
}
/* Raw data from MOBIData will be converted to html, css, fonts, media resources */
/* Parsed data will be available in MOBIRawml structure */
mobi_ret = mobi_parse_rawml(rawml, m);
if (mobi_ret != MOBI_SUCCESS) {
  printf("Failed to parse rawml\n Error code: %d\n", mobi_ret);
  mobi_free(m);
  mobi_free_rawml(rawml);
  return -1;
}

/* Do something useful here */
/* ... */
/* For examples how to access data in MOBIRawml structure see mobitool.c */
print_rawml_structure(rawml);
//print_content(rawml);
/* Free MOBIRawml structure */
mobi_free_rawml(rawml);

/* Free MOBIData structure */
mobi_free(m);

return 0;
}