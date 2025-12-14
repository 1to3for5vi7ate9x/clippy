# clipboard-history

## Project Type: basic

## Getting Started

### Prerequisites
- GCC or Clang compiler
- Make

### Building

```bash
make
```

### Running

```bash
./bin/clipboard-history
```

### Testing

```bash
make test
```

### Project Structure

```
.
├── src/
│   ├── main.c
│   └── clipboard-history.c
├── include/
│   └── clipboard-history.h
├── tests/
│   └── test_main.c
├── Makefile
├── README.md
└── .gitignore
```

## Development

### Compiler Flags
The project uses these compiler flags by default:
- `-Wall`: Enable all warnings
- `-Wextra`: Enable extra warnings
- `-Wpedantic`: Enable strict ISO C compliance
- `-std=c11`: Use C11 standard

### Adding Dependencies
For external libraries, update the `LDFLAGS` in the Makefile or add `find_package()` in CMakeLists.txt.

## License

[Add your license here]
