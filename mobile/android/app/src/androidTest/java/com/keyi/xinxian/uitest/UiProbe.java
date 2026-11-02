package com.keyi.xinxian.uitest;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.net.Uri;
import android.os.*;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.lang.reflect.*;

/** Runs in an isolated emulator, never scans Bluetooth or injects audio output. */
public final class UiProbe extends Instrumentation {
    private Activity activity;
    private Object ui;
    private int checks;
    private String scenario="normal";
    private static Object field(Object object,String name) {
        try { Field f=object.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(object); }
        catch(Exception e) { throw new RuntimeException(e); }
    }
    private void check(boolean value,String reason) { if(!value)throw new AssertionError(reason);checks++; }
    private void stage(String text) { Bundle b=new Bundle();b.putString("stage",text);sendStatus(0,b); }
    private ActivityMonitor pickerResult(int code,Intent data) {
        ActivityMonitor monitor=new ActivityMonitor() {
            @Override public ActivityResult onStartActivity(Intent intent) {
                return Intent.ACTION_OPEN_DOCUMENT.equals(intent.getAction())?new ActivityResult(code,data):null;
            }
        };
        addMonitor(monitor);return monitor;
    }
    private void click(Object value) { runOnMainSync(()->((View)value).performClick());waitForIdleSync(); }
    private void loaded() {
        long deadline=SystemClock.uptimeMillis()+5000;
        while((boolean)field(activity,"busy")&&SystemClock.uptimeMillis()<deadline)SystemClock.sleep(20);
        waitForIdleSync();check(!(boolean)field(activity,"busy"),"file load timeout");
    }
    private void screenshot(String name) throws Exception {
        waitForIdleSync();SystemClock.sleep(2200);
        Bitmap image=getUiAutomation().takeScreenshot();check(image!=null,"screenshot");
        File output=new File(getTargetContext().getExternalFilesDir(null),scenario+"_"+name+".png");
        try(OutputStream stream=new FileOutputStream(output)) { image.compress(Bitmap.CompressFormat.PNG,100,stream); }
        image.recycle();
    }
    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);if(arguments!=null)scenario=arguments.getString("scenario","normal");start();
    }
    @Override public void onStart() {
        Bundle result=new Bundle();
        try {
            stage("launch");
            Intent launch=new Intent().setClassName(getTargetContext().getPackageName(),"com.keyi.xinxian.guitar.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK);
            activity=startActivitySync(launch);waitForIdleSync();ui=field(activity,"ui");
            runOnMainSync(()->((Switch)field(ui,"animation")).setChecked(false));
            Button[] songs=(Button[])field(ui,"songs");
            int[] counts={25,564,491};long[] crc={0xf08df358L,0x5d01057fL,0x1dd77241L};
            for(int i=0;i<3;i++) {
                click(songs[i]);loaded();Object model=field(activity,"song");check(model!=null,"builtin parsed");
                check(((java.util.List<?>)field(model,"events")).size()==counts[i],"builtin event count");
                check((long)field(model,"crc32")==crc[i],"builtin checksum");
            }
            stage("three builtins parsed");
            for(String file:new String[]{"import.bin","invalid.bin"}) {
                Intent response=new Intent().setData(Uri.parse("content://com.keyi.xinxian.guitar.uitest.files/"+file)).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                ActivityMonitor picker=pickerResult(Activity.RESULT_OK,response);
                click(field(ui,"pick"));loaded();check(picker.getHits()==1,"system file picker requested");removeMonitor(picker);
                check((field(activity,"song")!=null)==file.equals("import.bin"),"external validation result");
                check(!((Button)field(ui,"upload")).isEnabled(),"offline upload disabled");
            }
            stage("external files checked");
            ActivityMonitor cancel=pickerResult(Activity.RESULT_CANCELED,null);
            click(field(ui,"pick"));removeMonitor(cancel);check(!(boolean)field(activity,"pickingFile"),"picker cancel cleanup");
            click(songs[1]);loaded();stage("library screenshot");screenshot("library");
            click(field(ui,"configure"));Button[] slots=(Button[])field(ui,"slots");
            click(slots[4]);check(((Button)field(ui,"upload")).getText().toString().contains("第5槽"),"slot selection");
            click(slots[3]);Button[] timbres=(Button[])field(ui,"timbres");
            String[] tones={"钢琴","明亮弦音","哇音"};
            for(int i=0;i<3;i++) { click(timbres[i]);check((int)field(activity,"selectedTimbre")==i,"timbre ID");check(timbres[i].getText().toString().equals(tones[i]),"timbre name"); }
            click(timbres[1]);
            check(slots[3].getText().toString().contains("待导入")&&slots[4].getText().toString().contains("待导入"),"both pending slots");
            android.graphics.Rect visible=new android.graphics.Rect();
            View upload=(View)field(ui,"upload");check(upload.getGlobalVisibleRect(visible)&&visible.height()==upload.getHeight(),"upload button always visible");
            View safe=(View)field(ui,"safe");
            if(Build.VERSION.SDK_INT>=30) {
                Insets bars=safe.getRootWindowInsets().getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());
                check(safe.getPaddingTop()>=bars.top&&safe.getPaddingBottom()>=bars.bottom,"real system bar safe area");
                runOnMainSync(()->{
                    WindowInsets simulated=new WindowInsets.Builder().setInsets(WindowInsets.Type.systemBars(),Insets.of(9,73,17,51))
                        .setInsets(WindowInsets.Type.displayCutout(),Insets.of(22,101,0,0)).build();
                    safe.dispatchApplyWindowInsets(simulated);
                });
                check(safe.getPaddingLeft()==22&&safe.getPaddingTop()==101&&safe.getPaddingRight()==17&&safe.getPaddingBottom()==51,"cutout/bar union");
                runOnMainSync(safe::requestApplyInsets);waitForIdleSync();
            }
            stage("insets checked");screenshot("upload");
            // Activity state must preserve the chosen score and settings on recreation.
            ActivityMonitor recreation=addMonitor("com.keyi.xinxian.guitar.MainActivity",null,false);
            runOnMainSync(activity::recreate);
            Activity next=waitForMonitorWithTimeout(recreation,5000);removeMonitor(recreation);
            check(next!=null,"activity recreated");activity=next;ui=field(activity,"ui");loaded();
            check((int)field(activity,"selectedBuiltin")==1&&(int)field(activity,"selectedSlot")==3&&(int)field(activity,"selectedTimbre")==1,"selection restored");
            check(field(activity,"song")!=null,"score restored");
            result.putString("result","PASS");result.putInt("checks",checks);result.putString("scenario",scenario);
            finish(Activity.RESULT_OK,result);
        } catch(Throwable error) {
            StringWriter stack=new StringWriter();error.printStackTrace(new PrintWriter(stack));result.putString("failure",stack.toString());finish(Activity.RESULT_CANCELED,result);
        }
    }
}
