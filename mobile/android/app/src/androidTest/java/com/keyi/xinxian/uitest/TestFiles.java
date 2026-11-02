package com.keyi.xinxian.uitest;

import android.content.*;
import android.database.*;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.*;

/** Test-only controlled documents. Not included in the delivered application. */
public final class TestFiles extends ContentProvider {
    @Override public boolean onCreate() { return true; }
    @Override public String getType(Uri uri) { return "application/octet-stream"; }
    @Override public Cursor query(Uri uri,String[] projection,String selection,String[] args,String order) {
        MatrixCursor cursor=new MatrixCursor(new String[]{OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE});
        cursor.addRow(new Object[]{uri.getLastPathSegment(),uri.getLastPathSegment().equals("import.bin")?400:17});return cursor;
    }
    @Override public ParcelFileDescriptor openFile(Uri uri,String mode) throws FileNotFoundException {
        String name=uri.getLastPathSegment();if(!name.equals("import.bin")&&!name.equals("invalid.bin"))throw new FileNotFoundException();
        File file=new File(getContext().getCacheDir(),name);
        try(OutputStream out=new FileOutputStream(file)) {
            if(name.equals("import.bin")) {
                try(InputStream in=getContext().getAssets().open("scores/happy_birthday_60bpm.bin")) { byte[] block=new byte[4096];int n;while((n=in.read(block))!=-1)out.write(block,0,n); }
            } else out.write(new byte[17]);
        } catch(IOException error) { throw new FileNotFoundException(error.toString()); }
        return ParcelFileDescriptor.open(file,ParcelFileDescriptor.MODE_READ_ONLY);
    }
    @Override public Uri insert(Uri uri,ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri,String where,String[] args) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri,ContentValues values,String where,String[] args) { throw new UnsupportedOperationException(); }
}
