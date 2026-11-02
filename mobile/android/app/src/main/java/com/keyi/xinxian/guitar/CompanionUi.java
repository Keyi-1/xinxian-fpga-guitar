package com.keyi.xinxian.guitar;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.content.res.ColorStateList;
import android.view.Gravity;
import android.view.View;
import android.widget.*;

/** Native, scrollable screens. All dimensions are dp, all text uses scalable sp. */
final class CompanionUi {
    static final int LIBRARY=0, DEVICE=1, SETTINGS=2, UPLOAD=3;
    static final int BG=0xff0b1321, CARD=0xff142134, LINE=0xff293d55, TEXT=0xfff3f6fc, MUTED=0xffaabbd0, CYAN=0xff46d9ed;
    final Activity activity;
    final LinearLayout safe;
    final MusicBackdropView backdrop;
    final TextView status, connection, fileName, uploadSong, log, capacity, result, progressText, pending;
    final Spinner devices;
    final Button scan, connect, disconnect, query, pick, upload, configure, review;
    final Button[] songs = new Button[3], slots = new Button[5], timbres = new Button[3];
    final Switch animation;
    final ProgressBar progress;
    private final View[] pages = new View[4];
    private final Button[] nav = new Button[3];
    private LinearLayout uploadFooter;
    private TextView targetHeading;
    private int page;

    CompanionUi(Activity activity) {
        this.activity=activity;
        FrameLayout root=new FrameLayout(activity); root.setBackgroundColor(BG);
        backdrop=new MusicBackdropView(activity);
        root.addView(backdrop, new FrameLayout.LayoutParams(-1, dp(205)));
        safe=column(); root.addView(safe,new FrameLayout.LayoutParams(-1,-1));
        LinearLayout header=row(); header.setPadding(dp(20),dp(10),dp(20),dp(8));
        ImageView logo=new ImageView(activity); logo.setImageResource(R.drawable.ic_launcher_foreground);
        header.addView(logo,new LinearLayout.LayoutParams(dp(44),dp(44)));
        TextView brand=text("弦心",25,TEXT); brand.setTypeface(null,Typeface.BOLD);
        header.addView(brand,new LinearLayout.LayoutParams(0,-2,1));
        status=text("○ 未连接",12,MUTED); status.setPadding(dp(10),dp(10),dp(10),dp(10));
        status.setBackground(shape(CARD,LINE)); status.setContentDescription("蓝牙连接状态，点击管理设备");
        status.setMinHeight(dp(48));status.setGravity(Gravity.CENTER);
        status.setOnClickListener(v->show(DEVICE)); header.addView(status);
        safe.addView(header);
        FrameLayout content=new FrameLayout(activity); safe.addView(content,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout library=page(content,LIBRARY);
        title(library,"曲库");
        LinearLayout sources=row();
        Button builtins=button("内置曲谱",true); Button phone=button("手机文件",false);
        weighted(sources,builtins); weighted(sources,phone); add(library,sources,8);
        builtins.setOnClickListener(v->show(LIBRARY));
        for(int i=0;i<songs.length;i++) {
            ScoreLibrary.Entry entry=ScoreLibrary.ENTRIES[i];
            songs[i]=button("♫   "+entry.title+"\n"+entry.bpm+" BPM · "+ScoreLibrary.duration(entry.samples),false);
            songs[i].setGravity(Gravity.START|Gravity.CENTER_VERTICAL); songs[i].setMinHeight(dp(82));
            songs[i].setContentDescription("选择内置曲谱 "+entry.title); add(library,songs[i],10);
        }
        pick=button("＋  从手机选择 .bin",false); add(library,pick,16); phone.setOnClickListener(v->pick.performClick());
        label(library,"已选择",22);
        fileName=text("选择一首曲谱，开始准备演奏",17,TEXT); fileName.setTextIsSelectable(true); add(library,fileName,5);
        configure=button("设置上传  →",true); add(library,configure,14); configure.setOnClickListener(v->show(UPLOAD));

        LinearLayout uploadPage=uploadPage(content);
        LinearLayout uploadHeading=row();Button back=button("‹",false);back.setContentDescription("返回曲库");
        uploadHeading.addView(back,new LinearLayout.LayoutParams(dp(48),dp(48)));
        TextView uploadTitle=text("  上传曲谱",24,TEXT);uploadTitle.setTypeface(null,Typeface.BOLD);uploadHeading.addView(uploadTitle);
        add(uploadPage,uploadHeading,0);back.setOnClickListener(v->show(LIBRARY));
        uploadSong=text("尚未选择曲谱",17,TEXT); add(uploadPage,uploadSong,12);
        LinearLayout target=row(); targetHeading=text("目标槽位",17,TEXT);
        target.addView(targetHeading,new LinearLayout.LayoutParams(0,-2,1)); query=button("刷新",false);query.setMinHeight(dp(48));query.setTextSize(14);target.addView(query); add(uploadPage,target,12);
        for(int i=0;i<5;i++) {
            slots[i]=button("",false); slots[i].setGravity(Gravity.START|Gravity.CENTER_VERTICAL);
            slots[i].setMinHeight(dp(52));slots[i].setTextSize(15);add(uploadPage,slots[i],7);
        }
        label(uploadPage,"音色",14); LinearLayout toneRow=row();
        for(int i=0;i<3;i++) { timbres[i]=button(ScoreLibrary.TIMBRES[i],false); timbres[i].setTextSize(14); weighted(toneRow,timbres[i]); }
        add(uploadPage,toneRow,8);
        upload=button("上传到第4槽",true); add(uploadFooter,upload,0);
        progress=new ProgressBar(activity,null,android.R.attr.progressBarStyleHorizontal); progress.setMax(100);
        progress.setProgressTintList(ColorStateList.valueOf(CYAN)); add(uploadFooter,progress,8);progress.setVisibility(View.GONE);
        progressText=text("",13,MUTED); add(uploadFooter,progressText,2);progressText.setVisibility(View.GONE);
        result=text("",14,TEXT); result.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE); add(uploadFooter,result,8);result.setVisibility(View.GONE);
        TextView ram=text("导入曲谱断电后需重新上传",12,MUTED); ram.setGravity(Gravity.CENTER); add(uploadFooter,ram,8);

        LinearLayout devicePage=page(content,DEVICE); title(devicePage,"连接乐器");
        connection=text("尚未连接蓝牙设备",15,MUTED); add(devicePage,connection,8);
        devices=new Spinner(activity); devices.setPopupBackgroundDrawable(shape(CARD,LINE)); add(devicePage,devices,16);
        LinearLayout actions=row(); scan=button("扫描蓝牙",true); connect=button("连接",false); weighted(actions,scan); weighted(actions,connect); add(devicePage,actions,10);
        disconnect=button("断开连接",false); add(devicePage,disconnect,10);
        capacity=text("连接后读取设备容量与槽位状态",14,MUTED); add(devicePage,capacity,18);
        label(devicePage,"操作记录",24);
        log=text("等待操作…",12,MUTED); log.setTextIsSelectable(true); log.setPadding(dp(12),dp(12),dp(12),dp(12)); log.setBackground(shape(CARD,LINE)); add(devicePage,log,8);

        LinearLayout settings=page(content,SETTINGS); title(settings,"设置");
        animation=new Switch(activity); animation.setText("音符动态背景"); animation.setTextSize(17); animation.setTextColor(TEXT); animation.setMinHeight(dp(60)); add(settings,animation,10);
        add(settings,text("轻缓漂浮的音符与粒子；上传时自动暂停。",14,MUTED),6);
        label(settings,"提交核对",30);
        pending=text("没有待核对的上传",14,MUTED); add(settings,pending,8);
        review=button("核对上次提交",false); add(settings,review,12);
        label(settings,"关于弦心",30); add(settings,text("内置曲谱与手机文件均以音符事件上传。\n实际演奏声音由 FPGA 实时生成。\n\n弦心 0.3.0",14,MUTED),10);

        LinearLayout navigation=row(); navigation.setPadding(dp(12),dp(7),dp(12),dp(7)); navigation.setBackground(shape(0xff101c2d,LINE));
        String[] labels={"♫  曲库","▣  设备","⚙  设置"};
        for(int i=0;i<3;i++) { final int selected=i; nav[i]=button(labels[i],false); weighted(navigation,nav[i]); nav[i].setOnClickListener(v->show(selected)); }
        safe.addView(navigation); activity.setContentView(root); show(LIBRARY);
    }
    void show(int value) {
        page=value; for(int i=0;i<pages.length;i++) pages[i].setVisibility(i==value?View.VISIBLE:View.GONE);
        for(int i=0;i<nav.length;i++) {
            boolean selected=i==(value==UPLOAD?LIBRARY:value);
            nav[i].setSelected(selected);nav[i].setTextColor(selected?CYAN:MUTED);
            nav[i].setBackground(new RippleDrawable(ColorStateList.valueOf(0x3058e3ef),shape(0xff101c2d,0xff101c2d),null));
        }
    }
    int page() { return page; }
    void selected(int song, int slot, int timbre, Xg3Protocol.SlotDescriptor[] descriptors) {
        targetHeading.setText(descriptors[0]==null?"目标槽位 · 待查询":"目标槽位");
        for(int i=0;i<songs.length;i++) outline(songs[i],i==song);
        for(int i=0;i<slots.length;i++) {
            Xg3Protocol.SlotDescriptor d=descriptors[i];
            String detail=d==null?"待查询":d.playable?d.eventCount+"事件 · "+ScoreLibrary.timbre(d.timbre):"待导入";
            String name=ScoreLibrary.slotTitle(i,d);
            slots[i].setText((i+1)+"   "+name+(i==slot?"   ✓":""));
            slots[i].setContentDescription("第"+(i+1)+"槽，"+name+"，"+detail+(i==slot?"，已选择":""));
            outline(slots[i],i==slot);
        }
        for(int i=0;i<timbres.length;i++) select(timbres[i],i==timbre);
        upload.setText("上传到第"+(slot+1)+"槽");
    }
    void select(Button button, boolean selected) {
        button.setSelected(selected); button.setTextColor(selected?BG:TEXT);
        button.setBackground(new RippleDrawable(ColorStateList.valueOf(0x4058e3ef),shape(selected?CYAN:CARD,selected?CYAN:LINE),null));
    }
    private void outline(Button button,boolean selected) {
        button.setSelected(selected);button.setTextColor(TEXT);
        button.setBackground(new RippleDrawable(ColorStateList.valueOf(0x3058e3ef),shape(CARD,selected?CYAN:LINE),null));
    }
    void setResult(String text) { result.setText(text);result.setVisibility(text.isEmpty()?View.GONE:View.VISIBLE); }
    private LinearLayout uploadPage(FrameLayout parent) {
        LinearLayout shell=column();parent.addView(shell,new FrameLayout.LayoutParams(-1,-1));pages[UPLOAD]=shell;
        ScrollView scroll=new ScrollView(activity);scroll.setFillViewport(true);
        LinearLayout body=column();body.setPadding(dp(20),dp(6),dp(20),dp(14));scroll.addView(body);
        shell.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        uploadFooter=column();uploadFooter.setPadding(dp(20),dp(8),dp(20),dp(10));uploadFooter.setBackgroundColor(BG);
        shell.addView(uploadFooter);return body;
    }
    private LinearLayout page(FrameLayout parent,int index) {
        ScrollView scroll=new ScrollView(activity); scroll.setFillViewport(true); scroll.setClipToPadding(false);
        LinearLayout body=column(); body.setPadding(dp(20),dp(6),dp(20),dp(26)); scroll.addView(body);
        parent.addView(scroll,new FrameLayout.LayoutParams(-1,-1)); pages[index]=scroll; return body;
    }
    private void title(LinearLayout parent,String title) { TextView t=text(title,28,TEXT); t.setTypeface(null,Typeface.BOLD); add(parent,t,14); }
    private void label(LinearLayout parent,String title,int gap) { TextView t=text(title,16,TEXT); t.setTypeface(null,Typeface.BOLD); add(parent,t,gap); }
    private LinearLayout column() { LinearLayout l=new LinearLayout(activity); l.setOrientation(LinearLayout.VERTICAL); return l; }
    private LinearLayout row() { LinearLayout l=new LinearLayout(activity); l.setOrientation(LinearLayout.HORIZONTAL); l.setGravity(Gravity.CENTER_VERTICAL); return l; }
    private TextView text(String text,int size,int color) { TextView t=new TextView(activity); t.setText(text); t.setTextSize(size); t.setTextColor(color); t.setFontFeatureSettings("kern"); return t; }
    private Button button(String label,boolean primary) {
        Button b=new Button(activity); b.setText(label); b.setTextSize(16); b.setAllCaps(false); b.setMinHeight(dp(52)); b.setMinimumWidth(0); b.setMinWidth(0); b.setPadding(dp(14),dp(10),dp(14),dp(10)); select(b,primary); return b;
    }
    private void add(LinearLayout parent,View child,int top) { LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2); p.topMargin=dp(top); parent.addView(child,p); }
    private void weighted(LinearLayout parent,View child) { LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(0,-2,1); if(parent.getChildCount()>0)p.leftMargin=dp(6); parent.addView(child,p); }
    private GradientDrawable shape(int color,int border) { GradientDrawable d=new GradientDrawable(); d.setColor(color); d.setCornerRadius(dp(16)); d.setStroke(dp(1),border); return d; }
    int dp(float value) { return Math.round(value*activity.getResources().getDisplayMetrics().density); }
}
