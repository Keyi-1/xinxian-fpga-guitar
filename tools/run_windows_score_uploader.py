"""Windows entry point, also usable from source with PyQt5 and pyserial."""
if __name__ == "__main__":
    import sys
    if len(sys.argv) == 3 and sys.argv[1] == '--smoke-test':
        from windows_score_uploader.smoke import run
        raise SystemExit(run(sys.argv[2]))
    if len(sys.argv) == 3 and sys.argv[1] == '--audio-smoke-test':
        from windows_score_uploader.media_smoke import run
        raise SystemExit(run(sys.argv[2]))
    from windows_score_uploader.window import main
    raise SystemExit(main())
